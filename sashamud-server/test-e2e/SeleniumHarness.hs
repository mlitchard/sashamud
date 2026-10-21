{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}

module SeleniumHarness
  ( withServer
  , webDriverTestWithClient
  , webDriverTestWithPage
  , successToken
  ) where

import           SashaPrelude

import           API.TSClient (client)
import           API.Types (SessionId (SessionId))
import           Control.Concurrent (threadDelay)
import           Control.Concurrent.Async (mapConcurrently_, race_)
import           Control.Concurrent.STM (atomically)
import           Control.Concurrent.STM.TMVar (putTMVar)
import           Control.Monad.Logger (runStdoutLoggingT)
import           Control.Monad.Trans.Reader (runReaderT)
import           Data.Aeson (Object, encode, object, (.=))
import           Data.Aeson.Key (fromString)
import           Data.Aeson.KeyMap (fromList)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 (pack)
import           Data.Pool (defaultPoolConfig, newPool, withResource)
import           Data.String.Interpolate (i)
import           Data.Text (intercalate)
import           Data.Text.Encoding (decodeUtf8', encodeUtf8)
import qualified Data.Text.IO as TIO
import           Data.Time.Clock.POSIX (getPOSIXTime)
import           Database.PostgreSQL.Simple (close, connectPostgreSQL)
import           Database.PostgreSQL.Simple.Migration
  ( MigrationResult (MigrationError, MigrationSuccess)
  , defaultOptions
  , runMigrations
  )
import           Engine.Simulation.SignalNetwork (gameLoop)
import           FakeProvider
  ( fakeApp
  , loginThroughFake
  , newFakeState
  , seedAccount
  )
import           GHC.IO (FilePath)
import           Model.Account
  ( ClientId (ClientId)
  , ClientSecret (ClientSecret)
  , OidcBaseUrl (OidcBaseUrl)
  , RedirectUri (RedirectUri)
  )
import           Model.Authorization (RoleName (Wizard))
import           Model.Core (defaultGameState, initialCounters)
import           Network.HTTP.Client
  ( Request (method, requestBody, requestHeaders)
  , RequestBody (RequestBodyLBS)
  , Response (responseBody, responseStatus)
  , defaultManagerSettings
  , httpLbs
  , managerResponseTimeout
  , newManager
  , parseRequest
  , responseTimeoutMicro
  )
import           Network.HTTP.Types.Status (statusIsSuccessful)
import           Network.Wai.Handler.Warp (testWithApplication)
import           Servant.Server.Internal.Handler (runHandler)
import           Server.App
  ( AppCtx (acDbPool, acLoginGate)
  , AppM (unAppM)
  , GameLog (GameLog)
  , OidcConfig (OidcConfig)
  , ScriptMessage (WorldReady)
  , newAppCtx
  )
import           Server.Migration (buildCommand)
import           Server.Server (app, appWithStaticFiles, deliverOutbound)
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))
import           Server.World (mintBootstrapToken, worldPrograms)
import           System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getTemporaryDirectory
  , removeFile
  )
import           System.Environment (lookupEnv)
import           System.Exit (ExitCode (ExitFailure), exitFailure)
import           System.FilePath ((<.>), (</>))
import           System.IO
  ( BufferMode (LineBuffering)
  , hClose
  , hSetBuffering
  , hSetEncoding
  , openTempFile
  , stdout
  , utf8
  )
import           System.Posix.Signals
  ( Handler (Catch)
  , installHandler
  , raiseSignal
  , sigUSR1
  )
import           System.Process (readProcessWithExitCode)
import           System.Random (randomIO)
import           Test.WebDriver
  ( Capabilities (_capabilitiesBrowserName, _capabilitiesGoogChromeOptions)
  , _driverManager
  , asyncJS
  , closeSession'
  , defaultCaps
  , defaultChromeOptions
  , mkManualDriver
  , openPage
  , setScriptTimeout
  , startSession'
  )
import           Test.WebDriver.Capabilities
  ( ChromeOptions (_chromeOptionsArgs, _chromeOptionsPrefs)
  )
import           Test.WebDriver.WD (WD, runWD)

successToken :: String
successToken = "success"

chromeCaps :: Capabilities
chromeCaps = defaultCaps
  { _capabilitiesBrowserName = Just "chrome"
  , _capabilitiesGoogChromeOptions = Just defaultChromeOptions
      { _chromeOptionsArgs = Just [ "--headless=new", "--disable-gpu", "--no-sandbox" ] }
  }

clipboardPrefs :: Int -> Object
clipboardPrefs port = fromList
  [ ( "profile.content_settings.exceptions.clipboard"
    , object [ fromString ("http://127.0.0.1:" <> show port <> ",*") .= object [ "setting" .= (1 :: Int) ] ]
    )
  ]

withServer :: (AppCtx -> IO ()) -> IO ()
withServer action = do
  hSetEncoding stdout utf8
  hSetBuffering stdout LineBuffering
  let logCfg = GameLog stderr Nothing
  connStr <- fromMaybe "dbname=sashamud" <$> lookupEnv "SASHA_DB_CONNSTR"
  migrationsDir <- fromMaybe "migrations" <$> lookupEnv "SASHA_MIGRATIONS_DIR"
  pool <- newPool (defaultPoolConfig (connectPostgreSQL (Data.ByteString.Char8.pack connStr)) close 60 10)
  migrated <- withResource pool (\conn -> runMigrations conn defaultOptions (buildCommand migrationsDir))
  case migrated of
    MigrationError err -> do
      hPutStrLn stderr ("migration failed: " <> err)
      exitFailure
    MigrationSuccess -> pure ()
  worldDir <- lookupEnv "SASHA_WORLD_DIR"
  dir <- case worldDir of
    Nothing  -> do
      hPutStrLn stderr "SASHA_WORLD_DIR unset"
      exitFailure
    Just worldPath -> pure worldPath
  manager <- newManager defaultManagerSettings
  fakeState <- newFakeState
  testWithApplication (pure (fakeApp fakeState)) $ \fakePort -> do
    let oidcConfig = OidcConfig
          (OidcBaseUrl ("http://127.0.0.1:" <> pack (show fakePort)))
          (ClientId "sashamud")
          (ClientSecret "sashamud-dev")
          (RedirectUri "http://127.0.0.1/api/auth/callback")
    ctx <- newAppCtx logCfg pool oidcConfig manager initialCounters
    _ <- installHandler sigUSR1 (Catch (atomically (putTMVar (acLoginGate ctx) WorldReady))) Nothing
    race_
      (race_ (gameLoop ctx defaultGameState) (deliverOutbound ctx))
      (do
        testWithApplication (pure (app ctx)) $ \port -> do
          seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "bootstrap")
          tmpDir <- getTemporaryDirectory
          (tokenPath, tokenHandle) <- openTempFile tmpDir "bootstrap-token"
          hClose tokenHandle
          minted <- runHandler (runReaderT (unAppM (mintBootstrapToken (PlayerNameVAL "bootstrap") tokenPath)) ctx)
          case minted of
            Left err -> error ("mint failed: " <> show err)
            Right () -> pure ()
          tokenBytes <- BS.readFile tokenPath
          token <- case decodeUtf8' tokenBytes of
            Left err -> error ("token file is not UTF-8: " <> show err)
            Right t  -> pure t
          paths <- worldPrograms dir
          forM_ paths $ \path -> do
            bytes <- BS.readFile path
            case decodeUtf8' bytes of
              Left err -> error ("lobby file is not UTF-8: " <> path <> " " <> show err)
              Right source -> do
                dslReq <- parseRequest ("http://127.0.0.1:" <> show port <> "/api/game/dsl")
                resp <- httpLbs dslReq
                  { method = "POST"
                  , requestHeaders = [("BEARER", encodeUtf8 token), ("Content-Type", "application/json")]
                  , requestBody = RequestBodyLBS (encode source)
                  } manager
                when (not (statusIsSuccessful (responseStatus resp))) $
                  error ("lobby delivery failed: " <> show (responseStatus resp) <> " " <> show (responseBody resp))
          threadDelay 6000000
          logoutReq <- parseRequest ("http://127.0.0.1:" <> show port <> "/api/game/logout")
          logoutResp <- httpLbs logoutReq
            { method = "DELETE"
            , requestHeaders = [("BEARER", encodeUtf8 token)]
            } manager
          when (not (statusIsSuccessful (responseStatus logoutResp))) $
            error ("bootstrap logout failed: " <> show (responseStatus logoutResp) <> " " <> show (responseBody logoutResp))
          raiseSignal sigUSR1
        action ctx)

indexhtml :: FilePath -> String
indexhtml path = [i|<html>
<head>
  <script type="module" src="#{path}"></script>
</head>
<body></body>
</html>|]

tsc :: FilePath -> IO () -> IO () -> IO ()
tsc path death continue = do
  tscres <- readProcessWithExitCode "tsc"
    [ path <.> "ts"
    , "--lib", "ES2021,DOM"
    , "--module", "esnext"
    ] ""
  case tscres of
    (ExitFailure _, stdOut, stdErr) -> do
      tsBytes <- BS.readFile $ path <.> "ts"
      let ts = case decodeUtf8' tsBytes of
                 Right t -> t
                 Left _  -> pack "(failed to decode file)"
      death
      TIO.putStrLn ts
      TIO.putStrLn "----------------------------------"
      TIO.putStrLn (pack [i|OUT: #{stdOut}
ERR: #{stdErr}|])
      exitFailure
    _ -> continue

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists fp = do
  exists <- doesFileExist fp
  when exists $ removeFile fp

webDriverTestWithClient :: AppCtx
                        -> [Text]
                        -> String
                        -> (WD (Maybe String) -> WD (Maybe String))
                        -> IO ()
webDriverTestWithClient ctx players jstest test = do
  rand :: Int <- randomIO
  now <- getPOSIXTime
  tmpDir <- getTemporaryDirectory
  _ <- createDirectoryIfMissing False tmpDir
  let testPath = show now <> show (rand * 1000000)
      clientName = "client-" <> testPath
      indexName = "index-" <> testPath
      death = mapConcurrently_ removeFileIfExists
        [ tmpDir </> clientName <.> "ts"
        , tmpDir </> clientName <.> "js"
        , tmpDir </> testPath <.> "ts"
        , tmpDir </> testPath <.> "js"
        , tmpDir </> indexName <.> "html"
        ]
  TIO.writeFile (tmpDir </> clientName <.> "ts") client
  TIO.writeFile (tmpDir </> indexName <.> "html") . pack . indexhtml $ testPath <.> "js"
  testWithApplication (pure (appWithStaticFiles ctx tmpDir))
    (\port -> do

      loginManager <- newManager defaultManagerSettings
      seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "raj")
      SessionId rajToken <- loginThroughFake loginManager port "raj"
      extraTokens <- mapM (\name -> do
          seedAccount (acDbPool ctx) Wizard (PlayerNameVAL name)
          SessionId t <- loginThroughFake loginManager port name
          pure ("\"" <> name <> "\": \"" <> t <> "\"")) players
      let tokensLiteral = intercalate ", " extraTokens

      TIO.writeFile (tmpDir </> testPath <.> "ts") (pack [i|
         import {
           API,
           SessionId,
           MessageFrom,
           MessageTo,
         } from "./client-#{testPath}.js";

         API.base = "http://127.0.0.1:#{port}";
         API.baseWS = "ws://127.0.0.1:#{port}";

         const sessionId: string = "#{rajToken}";
         const tokens: Record<string, string> = { #{tokensLiteral} };

         const testraw = async #{jstest}

         window["test"] = async resolve => {
           try {
             const sock = await API["/ws/game{Sec-WebSocket-Protocol}"](sessionId);

             sock.receive((msg: MessageFrom) => {});

             await new Promise(r => setTimeout(r, 1000));

             testraw(sessionId, sock, resolve);
           } catch(err) {
             if (err instanceof Response) {
               const text = await err.text();
               resolve("API error " + err.status + ": " + text);
             } else {
               resolve(String(err));
             }
           }
         };
      |])

      tsc (tmpDir </> testPath) death $ do

        mgr <- newManager defaultManagerSettings
          { managerResponseTimeout = responseTimeoutMicro (720 * 1000000) }
        res <- runStdoutLoggingT $ do
          driver <- mkManualDriver "127.0.0.1" 4444 "/wd/hub" []
          sess <- startSession' driver { _driverManager = mgr } chromeCaps "client"
          r <- runWD sess (do
            openPage $ "http://127.0.0.1:" <> show port </> indexName <.> "html"
            setScriptTimeout (Just 720000)
            test $ asyncJS [] [i|
              const done = arguments[0];
              const go = () => {
                if (window["test"]) { window["test"](done); } else { setTimeout(go, 50); }
              };
              go();|])
          closeSession' sess
          pure r

        case res of
          Just x | x == successToken -> death
          Just x                     -> death >> error x
          Nothing                    -> death >> error "TIMEOUT")

webDriverTestWithPage :: AppCtx -> (Text -> WD (Maybe String)) -> IO ()
webDriverTestWithPage ctx test = do
  dist <- fromMaybe "web/apps/sasha-web/dist" <$> lookupEnv "SASHA_WEB_DIST"
  testWithApplication (pure (appWithStaticFiles ctx dist))
    (\port -> do
      loginManager <- newManager defaultManagerSettings
      seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "raj")
      SessionId rajToken <- loginThroughFake loginManager port "raj"
      mgr <- newManager defaultManagerSettings
        { managerResponseTimeout = responseTimeoutMicro (720 * 1000000) }
      res <- runStdoutLoggingT $ do
        driver <- mkManualDriver "127.0.0.1" 4444 "/wd/hub" []
        sess <- startSession' driver { _driverManager = mgr }
          chromeCaps
            { _capabilitiesGoogChromeOptions = Just defaultChromeOptions
                { _chromeOptionsArgs = Just [ "--headless=new", "--disable-gpu", "--no-sandbox" ]
                , _chromeOptionsPrefs = Just (clipboardPrefs port)
                }
            }
          "page"
        r <- runWD sess (do
          openPage $ "http://127.0.0.1:" <> show port <> "/index.html#token=" <> unpack rajToken
          setScriptTimeout (Just 720000)
          test rajToken)
        closeSession' sess
        pure r
      case res of
        Just x | x == successToken -> pure ()
        Just x                     -> error x
        Nothing                    -> error "TIMEOUT")
