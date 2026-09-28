{-# LANGUAGE ExplicitNamespaces #-}

module Server.Server
  ( app
  , appWithStaticFiles
  , deliverOutbound
  , startServer
  ) where

import           SashaPrelude

import           API.Routes (SashaAPI)
import           API.Types
  ( AuthenticatedUser (AuthenticatedUser)
  , DSLSource (DSLSource)
  , LoginResponse (LoginResponse)
  , Routed (Routed)
  , SessionId (SessionId)
  )
import           Control.Concurrent (modifyMVar, modifyMVar_, readMVar)
import           Control.Concurrent.Async (race_)
import           Control.Concurrent.STM (atomically, readTChan, writeTChan)
import           Control.Exception (Handler (Handler), SomeException, catches)
import           Control.Monad (forever)
import           Control.Monad.Except (throwError)
import           Control.Monad.Reader (ask, runReaderT)
import qualified Data.ByteString.Char8 (pack)
import           Data.Map.Strict (delete, insert, lookup)
import qualified Data.Map.Strict (filter)
import           Data.String (fromString)
import           Data.UUID (toText)
import           Data.UUID.V4 (nextRandom)
import           Database.PostgreSQL.Simple (close, connectPostgreSQL)
import           Database.PostgreSQL.Simple.Migration
  ( MigrationResult (MigrationError, MigrationSuccess)
  , defaultOptions
  , runMigrations
  )
import           DSL.Builder
  ( WorldBuilderResult (resultCounters, resultGameState)
  )
import           DSL.Reify (reifyDSL)
import           Engine.Simulation.SignalNetwork (gameLoop)
import           GHC.IO (FilePath)
import           Network.Wai (Application)
import           Network.Wai.Handler.Warp (run)
import           Network.WebSockets (ConnectionException)
import           Servant
  ( HasServer (hoistServerWithContext)
  , NoContent (NoContent)
  , Proxy (Proxy)
  , Raw
  , ServerError (errBody)
  , err400
  , err401
  , err409
  , serveDirectoryFileServer
  , serveWithContext
  , type (:<|>) ((:<|>))
  )
import           Server.App
  ( AppCtx (acDSLChan, acGameLog, acOutbound, acSessions)
  , AppM (..)
  , GameLog (GameLog)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingSocket)
  , newAppCtx
  , sessionSend
  )
import           Server.Authentication (authProxy, sashaContext)
import           Server.GameWebSocket (gameWebSocket)
import           Server.Log
  ( LogEntry (PlayerLogin, SendDropped, SendError, SendFailed, ServerStart)
  , writeLog
  )
import           Server.Migration (buildCommand)
import           Server.Validator (PlayerNameVAL)
import           System.Environment (lookupEnv)
import           System.Exit (exitFailure)
import           Text.Read (readMaybe)

app :: AppCtx -> Application
app ctx = serveWithContext (Proxy @SashaAPI) sashaContext
  $ hoistServerWithContext (Proxy @SashaAPI) authProxy (flip runReaderT ctx . unAppM)
    (loginHandler :<|> logoutHandler :<|> gameWebSocket ctx :<|> dslHandler)

appWithStaticFiles :: AppCtx -> FilePath -> Application
appWithStaticFiles ctx tmpDir = serveWithContext andRaw sashaContext
  $ hoistServerWithContext andRaw authProxy (flip runReaderT ctx . unAppM)
    ((loginHandler :<|> logoutHandler :<|> gameWebSocket ctx :<|> dslHandler) :<|> serveDirectoryFileServer tmpDir)
  where andRaw = Proxy @(SashaAPI :<|> Raw)

loginHandler :: PlayerNameVAL -> AppM LoginResponse
loginHandler playerName = do
  ctx <- ask
  sessionId <- liftIO (SessionId . toText <$> nextRandom)
  alreadyActive <- liftIO . modifyMVar (acSessions ctx) $ \sessions ->
    if any hasActiveSession sessions
      then pure (sessions, True)
      else pure (insert sessionId (SessionPhase playerName AwaitingSocket)
                   (Data.Map.Strict.filter keepEntry sessions), False)
  when alreadyActive (throwError err409)
  liftIO $ writeLog (acGameLog ctx) (PlayerLogin playerName)
  pure (LoginResponse sessionId)
  where
    hasActiveSession (SessionPhase _ AwaitingSocket) = False
    hasActiveSession (SessionPhase n _)              = n == playerName
    keepEntry (SessionPhase n AwaitingSocket) = n /= playerName
    keepEntry _                               = True

logoutHandler :: SessionId -> AppM NoContent
logoutHandler sessionId = do
  ctx <- ask
  liftIO $ modifyMVar_ (acSessions ctx) (pure . delete sessionId)
  pure NoContent

dslHandler :: AuthenticatedUser -> DSLSource -> AppM NoContent
dslHandler (AuthenticatedUser sessionId) (DSLSource source) = do
  ctx <- ask
  sessions <- liftIO $ readMVar (acSessions ctx)
  case lookup sessionId sessions of
    Nothing -> throwError err401
    Just _ -> do
      result <- liftIO $ reifyDSL (unpack source)
      case result of
        Left err ->
          throwError err400 { errBody = fromString (show err) }
        Right dsl -> do
          liftIO . atomically $ writeTChan (acDSLChan ctx) dsl
          pure NoContent

deliverOutbound :: AppCtx -> IO ()
deliverOutbound ctx = forever $ do
  Routed sid wireMsg <- atomically (readTChan (acOutbound ctx))
  sessions <- readMVar (acSessions ctx)
  case lookup sid sessions >>= sessionSend of
    Nothing ->
      writeLog (acGameLog ctx) (SendDropped sid)
    Just sendMsgs ->
      catches (sendMsgs [wireMsg])
        [ Handler (\(_ :: ConnectionException) -> do
            writeLog (acGameLog ctx) (SendFailed sid)
            modifyMVar_ (acSessions ctx) (pure . delete sid))
        , Handler (\(e :: SomeException) ->
            writeLog (acGameLog ctx) (SendError sid (pack (show e))))
        ]

startServer :: WorldBuilderResult -> IO ()
startServer result = do
  port <- maybe 8081 readPort <$> lookupEnv "SASHA_WEB_PORT"
  connStr <- fromMaybe "dbname=sashamud" <$> lookupEnv "SASHA_DB_CONNSTR"
  migrationsDir <- fromMaybe "migrations" <$> lookupEnv "SASHA_MIGRATIONS_DIR"
  conn <- connectPostgreSQL (Data.ByteString.Char8.pack connStr)
  migrated <- runMigrations conn defaultOptions (buildCommand migrationsDir)
  close conn
  case migrated of
    MigrationError err -> do
      hPutStrLn stderr ("migration failed: " <> err)
      exitFailure
    MigrationSuccess -> pure ()
  let logCfg = GameLog stderr
  ctx <- newAppCtx logCfg (resultCounters result)
  writeLog logCfg (ServerStart port)
  hPutStrLn stderr ("sasha-web server starting on port " <> show port)
  race_
    (race_ (gameLoop ctx (resultGameState result)) (deliverOutbound ctx))
    (run port (app ctx))

readPort :: String -> Int
readPort s = fromMaybe 8081 (readMaybe s)
