{-# LANGUAGE ExplicitNamespaces #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Server.Server
  ( startServer
  ) where

import SashaPrelude

import API.Routes (SashaAPI)
import API.Types
  ( LoginResponse (LoginResponse)
  , MessageTo (MessageTo)
  , PlayerJoined (PlayerJoined)
  , PlayerName
  , SessionId (SessionId)
  )
import Control.Concurrent (readMVar)
import Control.Concurrent.Async (race_)
import Control.Concurrent.STM (atomically, readTChan, writeTChan)
import Control.Monad (forever)
import Control.Monad.Reader (ask, runReaderT)
import Data.Aeson (eitherDecode, encode)
import Data.Map.Strict (lookup)
import Data.UUID (toText)
import Data.UUID.V4 (nextRandom)
import Engine.Simulation.EffectNetwork (gameLoop)
import Model.Core (GameState, PossibilityGraph)
import Model.WireProtocol (WireMessage)
import Network.Wai (Application)
import Network.Wai.Handler.Warp (run)
import Network.WebSockets (DataMessage (Binary, Text), WebSocketsData (fromDataMessage, fromLazyByteString, toLazyByteString))
import Servant
  ( HasServer (hoistServerWithContext)
  , Proxy (Proxy)
  , serveWithContext
  , type (:<|>) ((:<|>))
  )
import Server.App
  ( AppCtx (acConnections, acJoinChan, acOutbound, acGameLog)
  , AppM (..)
  , GameLog (GameLog)
  , newAppCtx
  )
import Server.Authentication (authProxy, sashaContext)
import Server.GameWebSocket (gameWebSocket)
import Server.Log (LogEntry (PlayerLogin, ServerStart), writeLog)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

instance WebSocketsData WireMessage where
  toLazyByteString = encode
  fromLazyByteString lbs = case eitherDecode lbs of
    Right msg -> msg
    Left err  -> error $ "WireMessage decode failed: " <> err
  fromDataMessage (Text lbs _) = fromLazyByteString lbs
  fromDataMessage (Binary lbs) = fromLazyByteString lbs

app :: AppCtx -> Application
app ctx = serveWithContext (Proxy @SashaAPI) sashaContext
  $ hoistServerWithContext (Proxy @SashaAPI) authProxy (flip runReaderT ctx . unAppM)
    (loginHandler :<|> gameWebSocket ctx)

loginHandler :: PlayerName -> AppM LoginResponse
loginHandler playerName = do
  ctx <- ask
  sessionId <- liftIO (SessionId . toText <$> nextRandom)
  liftIO . atomically $
    writeTChan (acJoinChan ctx) (PlayerJoined sessionId playerName)
  liftIO $ writeLog (acGameLog ctx) (PlayerLogin playerName)
  pure (LoginResponse sessionId)

deliverOutbound :: AppCtx -> IO ()
deliverOutbound ctx = forever $ do
  MessageTo sid wireMsg <- atomically (readTChan (acOutbound ctx))
  conns <- readMVar (acConnections ctx)
  case lookup sid conns of
    Nothing -> pure ()
    Just sendMsgs -> sendMsgs [wireMsg]

startServer :: GameState -> PossibilityGraph -> IO ()
startServer initialGS pg = do
  port <- maybe 8081 readPort <$> lookupEnv "SASHA_WEB_PORT"
  let logCfg = GameLog stderr
  ctx <- newAppCtx logCfg
  writeLog logCfg (ServerStart port)
  hPutStrLn stderr ("sasha-web server starting on port " <> show port)
  race_
    (race_ (gameLoop ctx initialGS pg) (deliverOutbound ctx))
    (run port (app ctx))

readPort :: String -> Int
readPort s = fromMaybe 8081 (readMaybe s)
