{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE QuasiQuotes         #-}
{-# LANGUAGE ScopedTypeVariables #-}

module SeleniumHarness
  ( withServer
  , webDriverTestWithClient
  , successToken
  ) where

import           SashaPrelude

import           API.TSClient (client)
import           API.Types (SessionId (SessionId))
import           Control.Concurrent.Async (mapConcurrently_, race_)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 (pack)
import           Data.Pool (defaultPoolConfig, newPool, withResource)
import           Data.String.Interpolate (i)
import           Data.Text (intercalate)
import           Data.Text.Encoding (decodeUtf8')
import qualified Data.Text.IO as TIO
import           Data.Time.Clock.POSIX (getPOSIXTime)
import           Database.PostgreSQL.Simple (close, connectPostgreSQL)
import           Database.PostgreSQL.Simple.Migration
  ( MigrationResult (MigrationError, MigrationSuccess)
  , defaultOptions
  , runMigrations
  )
import           DSL.Builder (WorldBuilderResult (resultCounters))
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
import           Network.HTTP.Client
  ( defaultManagerSettings
  , managerResponseTimeout
  , newManager
  , responseTimeoutMicro
  )
import           Network.Wai.Handler.Warp (testWithApplication)
import           SashaMudWorld (buildResult, gameState)
import           Server.App
  ( AppCtx (acDbPool)
  , GameLog (GameLog)
  , OidcConfig (OidcConfig)
  , newAppCtx
  )
import           Server.Migration (buildCommand)
import           Server.Server (appWithStaticFiles, deliverOutbound)
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))
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
  , hSetBuffering
  , hSetEncoding
  , stdout
  , utf8
  )
import           System.Process (readProcessWithExitCode)
import           System.Random (randomIO)
import           Test.WebDriver
  ( Browser (chromeOptions)
  , WD
  , WDConfig (wdHTTPManager)
  , asyncJS
  , chrome
  , defaultConfig
  , openPage
  , runSession
  , setScriptTimeout
  , useBrowser
  )

successToken :: String
successToken = "success"

withServer :: (AppCtx -> IO ()) -> IO ()
withServer action = do
  hSetEncoding stdout utf8
  hSetBuffering stdout LineBuffering
  let logCfg = GameLog stderr
  connStr <- fromMaybe "dbname=sashamud" <$> lookupEnv "SASHA_DB_CONNSTR"
  migrationsDir <- fromMaybe "migrations" <$> lookupEnv "SASHA_MIGRATIONS_DIR"
  pool <- newPool (defaultPoolConfig (connectPostgreSQL (Data.ByteString.Char8.pack connStr)) close 60 10)
  migrated <- withResource pool (\conn -> runMigrations conn defaultOptions (buildCommand migrationsDir))
  case migrated of
    MigrationError err -> do
      hPutStrLn stderr ("migration failed: " <> err)
      exitFailure
    MigrationSuccess -> pure ()
  manager <- newManager defaultManagerSettings
  fakeState <- newFakeState
  testWithApplication (pure (fakeApp fakeState)) $ \fakePort -> do
    let oidcConfig = OidcConfig
          (OidcBaseUrl ("http://127.0.0.1:" <> pack (show fakePort)))
          (ClientId "sashamud")
          (ClientSecret "sashamud-dev")
          (RedirectUri "http://127.0.0.1/api/auth/callback")
    ctx <- newAppCtx logCfg pool oidcConfig manager (resultCounters buildResult)
    race_
      (race_ (gameLoop ctx gameState) (deliverOutbound ctx))
      (action ctx)

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
      seedAccount (acDbPool ctx) Wizard (PlayerNameVAL "Raj")
      SessionId rajToken <- loginThroughFake loginManager port "Raj"
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
        res <-
          runSession
            (useBrowser
               chrome
                 { chromeOptions =
                     [ "--headless=new"
                     , "--disable-gpu"
                     , "--no-sandbox"
                     ]
                 }
                 defaultConfig { wdHTTPManager = Just mgr })
            (do
            openPage $ "http://127.0.0.1:" <> show port </> indexName <.> "html"
            setScriptTimeout 720000
            test $ asyncJS [] [i|test(arguments[0])|])

        case res of
          Just x | x == successToken -> death
          Just x                     -> death >> error x
          Nothing                    -> death >> error "TIMEOUT")
