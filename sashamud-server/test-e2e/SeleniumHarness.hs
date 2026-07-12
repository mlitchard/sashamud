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
import           Control.Concurrent.Async (mapConcurrently_, race_)
import qualified Data.ByteString as BS
import           Data.String.Interpolate (i)
import           Data.Text.Encoding (decodeUtf8')
import qualified Data.Text.IO as TIO
import           Data.Time.Clock.POSIX (getPOSIXTime)
import           Engine.Simulation.SignalNetwork (gameLoop)
import           GHC.IO (FilePath)
import           Network.HTTP.Client
  ( defaultManagerSettings
  , managerResponseTimeout
  , newManager
  , responseTimeoutMicro
  )
import           Network.Wai.Handler.Warp (testWithApplication)
import           SashaMudWorld (gameState, possibilityGraph)
import           Server.App (AppCtx, GameLog (GameLog), newAppCtx)
import           Server.Server (appWithStaticFiles, deliverOutbound)
import           System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getTemporaryDirectory
  , removeFile
  )
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
  ctx <- newAppCtx logCfg
  race_
    (race_ (gameLoop ctx gameState possibilityGraph) (deliverOutbound ctx))
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
                        -> String
                        -> (WD (Maybe String) -> WD (Maybe String))
                        -> IO ()
webDriverTestWithClient ctx jstest test = do
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

      TIO.writeFile (tmpDir </> testPath <.> "ts") (pack [i|
         import {
           API,
           LoginResponse,
           SessionId,
           PlayerNameUNV,
           MessageFrom,
           MessageTo,
         } from "./client-#{testPath}.js";

         API.base = "http://127.0.0.1:#{port}";
         API.baseWS = "ws://127.0.0.1:#{port}";

         const testraw = async #{jstest}

         window["test"] = async resolve => {
           try {
             const playerName = "test" + Math.random().toString(36).replace(/[^a-z]/g, "").substring(0, 8);
             const sessionId: string = await API["/api/game/login(PlayerNameUNV)"](playerName);
             if (!sessionId) {
               resolve("Login failed: no SessionId returned");
               return;
             }

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
