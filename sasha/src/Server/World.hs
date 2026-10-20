{-# LANGUAGE QuasiQuotes #-}

module Server.World
  ( WorldLoadFailure (WorldDecodeFailed, WorldReifyFailed, WorldBuildFailed)
  , loadWorld
  , mintBootstrapToken
  , worldLoadFailureText
  , worldPrograms
  ) where

import           SashaPrelude

import           API.Types (AuthenticatedUser, SessionId (SessionId))
import           Control.Concurrent (modifyMVar, threadDelay)
import           Control.Monad (foldM)
import           Control.Monad.Except (ExceptT, throwError)
import           Control.Monad.Reader (ask)
import           Crypto.Random (getRandomBytes)
import           Data.ByteArray.Encoding
  ( Base (Base64URLUnpadded)
  , convertToBase
  )
import           Data.ByteString (ByteString)
import qualified Data.ByteString (readFile)
import           Data.List (isSuffixOf, sort)
import qualified Data.Map.Strict (filter, insert)
import           Data.Pool (withResource)
import           Data.String (fromString)
import           Data.Text.Encoding (decodeUtf8')
import           Data.Text.Encoding.Error (UnicodeException)
import qualified Data.Text.IO (writeFile)
import           Data.Time.Clock (secondsToNominalDiffTime)
import           Database.PostgreSQL.Simple (Only (Only), query)
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           DSL.Builder
  ( WorldBuilderError
  , WorldBuilderResult (WorldBuilderResult, resultCounters, resultGameState)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           DSL.Reify (reifyDSL)
import           GHC.IO (FilePath)
import           Language.Haskell.Interpreter (InterpreterError)
import           Model.Account (AccessToken (AccessToken), AuthentikUserId)
import           Model.Core (defaultGameState)
import           Model.GID (GID (GID))
import           Model.Jwt
  ( Credentials (Credentials)
  , Jwt (unJwt)
  , hashToken
  , makeJwtForTesting
  , tryAddHashAndJwt
  )
import           Model.Mid (Mid, unMid)
import           Servant (ServerError (errBody), err409, err500)
import           Server.App
  ( AppCtx (acDbPool, acSessions)
  , AppM
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingSocket)
  , initialCounters
  )
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))
import           System.Directory (doesDirectoryExist, listDirectory)

type WorldLoadFailure :: Type
data WorldLoadFailure = WorldDecodeFailed UnicodeException
                      | WorldReifyFailed InterpreterError
                      | WorldBuildFailed WorldBuilderError
  deriving stock (Generic, Show)

worldPrograms :: FilePath -> IO [FilePath]
worldPrograms dir = do
  entries <- listDirectory dir
  found <- forM (sort entries) $ \entry -> do
    let path = dir <> "/" <> entry
    isDir <- doesDirectoryExist path
    if isDir
      then worldPrograms path
      else pure (filter (".dsl" `isSuffixOf`) [path])
  pure (mconcat found)

loadWorld :: FilePath -> ExceptT WorldLoadFailure IO WorldBuilderResult
loadWorld worldDir = do
  let runSubmission prev path = do
        bytes   <- liftIO (Data.ByteString.readFile path)
        source  <- case decodeUtf8' bytes of
          Left err   -> throwError (WorldDecodeFailed err)
          Right text -> pure ("{-# LINE 1 \"" <> path <> "\" #-}\n" <> unpack text)
        reified <- liftIO (reifyDSL source)
        case reified of
          Left err  -> throwError (WorldReifyFailed err)
          Right dsl ->
            case runWorldBuilder (interpretDSL dsl) (initialBuilderState (resultGameState prev) (resultCounters prev)) of
              Left err   -> throwError (WorldBuildFailed err)
              Right next -> pure next
  programs <- liftIO (worldPrograms worldDir)
  foldM runSubmission (WorldBuilderResult defaultGameState initialCounters []) programs

worldLoadFailureText :: WorldLoadFailure -> String
worldLoadFailureText (WorldDecodeFailed err) = "Failed to decode world source: " <> show err
worldLoadFailureText (WorldReifyFailed err) = "Failed to reify world source: " <> show err
worldLoadFailureText (WorldBuildFailed err) = "Failed to build game state: " <> show err

mintBootstrapToken :: PlayerNameVAL -> FilePath -> AppM ()
mintBootstrapToken playerName@(PlayerNameVAL name) path = do
  ctx <- ask
  let awaitAccount announced = do
        rows :: [(Mid AuthenticatedUser, AuthentikUserId)] <-
          liftIO . withResource (acDbPool ctx) $ \conn ->
            query conn bootstrapQuery (Only name)
        case rows of
          []        -> do
            when (not announced) (liftIO (hPutStrLn stderr ("bootstrap account missing: " <> unpack name <> ", waiting")))
            liftIO (threadDelay 1000000)
            awaitAccount True
          [account] -> pure account
          _         -> throwError err500 { errBody = fromString ("bootstrap account ambiguous: " <> unpack name) }
  (userId, authentikUserId) <- awaitAccount False
  tokenBytes :: ByteString <- liftIO (getRandomBytes 32)
  let tokenRaw = convertToBase Base64URLUnpadded tokenBytes :: ByteString
  access <- case decodeUtf8' tokenRaw of
    Left _  -> throwError err500
    Right t -> pure (AccessToken t)
  hash <- liftIO (hashToken access)
  minted <- liftIO (makeJwtForTesting (secondsToNominalDiffTime 300) (Credentials authentikUserId) hash)
  jwt <- case minted of
    Left err -> throwError err500 { errBody = fromString ("token mint failed: " <> show err) }
    Right j  -> pure j
  tokenText <- case decodeUtf8' (unJwt jwt) of
    Left _  -> throwError err500
    Right t -> pure t
  tryAddHashAndJwt userId hash jwt
  let sessionId = SessionId tokenText
      agentGid = GID (unMid userId)
      hasActiveSession (SessionPhase _ _ AwaitingSocket) = False
      hasActiveSession (SessionPhase n _ _)              = n == playerName
      keepEntry (SessionPhase n _ AwaitingSocket) = n /= playerName
      keepEntry _                                 = True
  alreadyActive <- liftIO . modifyMVar (acSessions ctx) $ \sessions ->
    if any hasActiveSession sessions
      then pure (sessions, True)
      else pure (Data.Map.Strict.insert sessionId (SessionPhase playerName agentGid AwaitingSocket)
                   (Data.Map.Strict.filter keepEntry sessions), False)
  when alreadyActive (throwError err409)
  liftIO (Data.Text.IO.writeFile path tokenText)
  where
    bootstrapQuery =
      [sql|
        SELECT credentials.user_id, credentials.authentik_user_id FROM credentials
          JOIN users ON users.user_id = credentials.user_id
          JOIN agents ON agents.agent_id = users.user_id
          WHERE agents.name = ?
            AND users.status = 'active'
      |]
