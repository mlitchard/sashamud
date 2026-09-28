{-# LANGUAGE ExplicitNamespaces #-}

module Server.Server
  ( app
  , appWithStaticFiles
  , deliverOutbound
  , startServer
  ) where

import           SashaPrelude

import           API.Routes (AuthAPI, SashaAPI)
import           API.Types
  ( AuthenticatedUser (AuthenticatedUser)
  , DSLSource (DSLSource)
  , Routed (Routed)
  , SessionId (SessionId)
  )
import           Control.Concurrent (modifyMVar_, readMVar)
import           Control.Concurrent.Async (race_)
import           Control.Concurrent.STM (atomically, readTChan, writeTChan)
import           Control.Exception (Handler (Handler), SomeException, catches)
import           Control.Monad (forever)
import           Control.Monad.Except (throwError)
import           Control.Monad.Reader (ask, runReaderT)
import qualified Data.ByteString.Char8 (pack)
import           Data.Map.Strict (delete, lookup)
import           Data.Pool (defaultPoolConfig, newPool, withResource)
import           Data.String (fromString)
import           Data.Text.Encoding (encodeUtf8)
import           Database.PostgreSQL.Simple
  ( Only (Only)
  , close
  , connectPostgreSQL
  , execute
  )
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
import           Model.Account
  ( ClientId (ClientId)
  , ClientSecret (ClientSecret)
  , OidcBaseUrl (OidcBaseUrl)
  , RedirectUri (RedirectUri)
  )
import           Network.HTTP.Client.TLS (newTlsManager)
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
  , serveDirectoryFileServer
  , serveWithContext
  , type (:<|>) ((:<|>))
  )
import           Server.App
  ( AppCtx (acDSLChan, acDbPool, acGameLog, acOutbound, acSessions)
  , AppM (..)
  , GameLog (GameLog)
  , OidcConfig (OidcConfig)
  , newAppCtx
  , sessionSend
  )
import           Server.Authentication
  ( authAvailable
  , authCallback
  , authProxy
  , authStart
  , sashaContext
  , tokenDigest
  )
import           Server.GameWebSocket (gameWebSocket)
import           Server.Log
  ( LogEntry (SendDropped, SendError, SendFailed, ServerStart)
  , writeLog
  )
import           Server.Migration (buildCommand)
import           System.Environment (lookupEnv)
import           System.Exit (exitFailure)
import           Text.Read (readMaybe)

app :: AppCtx -> Application
app ctx = serveWithContext withAuth (sashaContext ctx)
  $ hoistServerWithContext withAuth authProxy (flip runReaderT ctx . unAppM)
    ((logoutHandler :<|> gameWebSocket ctx :<|> dslHandler) :<|> (authStart :<|> authCallback :<|> authAvailable))
  where withAuth = Proxy @(SashaAPI :<|> AuthAPI)

appWithStaticFiles :: AppCtx -> FilePath -> Application
appWithStaticFiles ctx tmpDir = serveWithContext andRaw (sashaContext ctx)
  $ hoistServerWithContext andRaw authProxy (flip runReaderT ctx . unAppM)
    ((logoutHandler :<|> gameWebSocket ctx :<|> dslHandler) :<|> (authStart :<|> authCallback :<|> authAvailable) :<|> serveDirectoryFileServer tmpDir)
  where andRaw = Proxy @(SashaAPI :<|> AuthAPI :<|> Raw)

logoutHandler :: SessionId -> AppM NoContent
logoutHandler sessionId@(SessionId token) = do
  ctx <- ask
  _ <- liftIO . withResource (acDbPool ctx) $ \conn ->
    execute conn "DELETE FROM tokens WHERE token_digest = ?" (Only (tokenDigest (encodeUtf8 token)))
  liftIO $ modifyMVar_ (acSessions ctx) (pure . delete sessionId)
  pure NoContent

dslHandler :: AuthenticatedUser -> DSLSource -> AppM NoContent
dslHandler (AuthenticatedUser sessionId _ _) (DSLSource source) = do
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
  pool <- newPool (defaultPoolConfig (connectPostgreSQL (Data.ByteString.Char8.pack connStr)) close 60 10)
  migrated <- withResource pool (\conn -> runMigrations conn defaultOptions (buildCommand migrationsDir))
  case migrated of
    MigrationError err -> do
      hPutStrLn stderr ("migration failed: " <> err)
      exitFailure
    MigrationSuccess -> pure ()
  oidcBaseUrl <- fromMaybe "http://127.0.0.1:9000" <$> lookupEnv "SASHA_OIDC_BASE_URL"
  oidcClientId <- fromMaybe "sashamud" <$> lookupEnv "SASHA_OIDC_CLIENT_ID"
  oidcClientSecret <- fromMaybe "sashamud-dev" <$> lookupEnv "SASHA_OIDC_CLIENT_SECRET"
  oidcRedirectUri <- fromMaybe "http://localhost:8081/api/auth/callback" <$> lookupEnv "SASHA_OIDC_REDIRECT_URI"
  let oidcConfig = OidcConfig
        (OidcBaseUrl (pack oidcBaseUrl))
        (ClientId (pack oidcClientId))
        (ClientSecret (pack oidcClientSecret))
        (RedirectUri (pack oidcRedirectUri))
  manager <- newTlsManager
  let logCfg = GameLog stderr
  ctx <- newAppCtx logCfg pool oidcConfig manager (resultCounters result)
  writeLog logCfg (ServerStart port)
  hPutStrLn stderr ("sasha-web server starting on port " <> show port)
  race_
    (race_ (gameLoop ctx (resultGameState result)) (deliverOutbound ctx))
    (run port (app ctx))

readPort :: String -> Int
readPort s = fromMaybe 8081 (readMaybe s)
