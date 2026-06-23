{-# LANGUAGE ExplicitNamespaces #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module Server.Server
  ( startServer
  ) where

import SashaPrelude

import API.Routes (SashaAPI)
import API.Types (LoginResponse (LoginResponse), MessageTo (MessageTo), PlayerName (PlayerName))
import Control.Concurrent.Async (race_)
import Control.Concurrent.STM
  ( TVar
  , atomically
  , modifyTVar'
  , newEmptyTMVarIO
  , newTVarIO
  , readTVar
  , writeTChan
  , writeTVar
  )
import Control.Monad.Reader (ReaderT (..), asks)
import Data.Aeson (eitherDecode, encode)
import Data.Map.Strict (insert, lookup)
import Data.Set (singleton)
import Data.UUID (toText)
import Data.UUID.V4 (nextRandom)
import Engine.Simulation.EffectNetwork (gameLoop)
import Lens.Micro.Platform (set, view)
import Model.Core
  ( Agent (Agent, _agentShortName, _agentDescription, _agentTitle, _agentActionManagement, _agentCurrentScene, _agentKind)
  , AgentKind (PlayerAgent)
  , AgentMap (AgentMap)
  , GIDToDataMap (GIDToDataMap)
  , GameState
  , PossibilityGraph
  , agentMap
  , defaultActionManagement
  , getAgentMap
  , sceneAgents
  , sceneMap
  , world
  , getGIDToDataMap
  )
import Model.GID (GID (GID))
import Model.RichText (TextColor (White), colored)
import Model.WireProtocol (WireMessage (ChatMessage))
import Network.Wai (Application, Request)
import Network.Wai.Handler.Warp (run)
import Network.WebSockets (DataMessage (Binary, Text), WebSocketsData (fromDataMessage, fromLazyByteString, toLazyByteString))
import Servant
  ( Handler
  , HasServer (hoistServerWithContext)
  , Proxy (Proxy)
  , serveWithContext
  , type (:<|>) ((:<|>))
  )
import Servant.Server.Experimental.Auth (AuthHandler)
import Server.App
  ( AppCtx (acNextAgentId, acOutbound, acPlayerMap, acRegistry, acGameLog)
  , GameLog (GameLog)
  , newAppCtx
  )
import Server.Authentication (sashaContext)
import Server.GameWebSocket (gameWebSocket)
import Server.Log (LogEntry (PlayerLogin, ServerStart), writeLog)
import Server.Session
  ( GameSession (GameSession)
  , addGameSession
  )
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data ServerCtx = ServerCtx
  { srvAppCtx        :: AppCtx
  , srvGameStateTVar :: TVar GameState
  }

type AppM = ReaderT ServerCtx Handler

instance WebSocketsData WireMessage where
  toLazyByteString = encode
  fromLazyByteString lbs = case eitherDecode lbs of
    Right msg -> msg
    Left err  -> error $ "WireMessage decode failed: " <> err
  fromDataMessage (Text lbs _) = fromLazyByteString lbs
  fromDataMessage (Binary lbs) = fromLazyByteString lbs

app :: ServerCtx -> Application
app sctx = serveWithContext (Proxy @SashaAPI) sashaContext
  $ hoistServerWithContext (Proxy @SashaAPI) (Proxy @'[AuthHandler Request Text]) (flip runReaderT sctx)
    (loginHandler :<|> gameWebSocket (srvAppCtx sctx) (acRegistry (srvAppCtx sctx)))

loginHandler :: PlayerName -> AppM LoginResponse
loginHandler (PlayerName playerName) = do
  ctx <- asks srvAppCtx
  let registry = acRegistry ctx
  gsTVar <- asks srvGameStateTVar
  sessionId <- liftIO (toText <$> nextRandom)
  liftIO . atomically $ do
    agentId <- readTVar (acNextAgentId ctx)
    writeTVar (acNextAgentId ctx) (agentId + 1)
    let agentGid = GID agentId
        lobbyGid = GID 0
        agent = Agent
          { _agentShortName        = playerName
          , _agentDescription      = colored White "A newly arrived adventurer."
          , _agentTitle            = ""
          , _agentActionManagement = defaultActionManagement
          , _agentCurrentScene     = lobbyGid
          , _agentKind             = PlayerAgent
          }
    gs <- readTVar gsTVar
    let gsWorld = view world gs
        am' = insert agentGid agent (view (agentMap . getAgentMap) gsWorld)
        lobbyScene = case lookup lobbyGid (view (sceneMap . getGIDToDataMap) gsWorld) of
              Just s  -> s
              Nothing -> error "Login: lobby scene not in sceneMap"
        lobbyScene' = set sceneAgents (view sceneAgents lobbyScene <> singleton agentGid) lobbyScene
        gsWorld' = set agentMap (AgentMap am')
                 (set sceneMap (GIDToDataMap (insert lobbyGid lobbyScene' (view (sceneMap . getGIDToDataMap) gsWorld))) gsWorld)
    writeTVar gsTVar (set world gsWorld' gs)
    modifyTVar' (acPlayerMap ctx) (insert sessionId agentGid)
  sendMsgsTVar <- liftIO newEmptyTMVarIO
  shutdownVar <- liftIO (newTVarIO False)
  let session = GameSession sessionId sendMsgsTVar shutdownVar
  liftIO (addGameSession registry sessionId session)
  liftIO . atomically $
    writeTChan (acOutbound ctx) (MessageTo sessionId (ChatMessage ("Welcome, " <> playerName <> "!")))
  liftIO $ writeLog (acGameLog ctx) (PlayerLogin playerName)
  pure (LoginResponse sessionId)

startServer :: GameState -> PossibilityGraph -> IO ()
startServer initialGS pg = do
  port <- maybe 8081 readPort <$> lookupEnv "SASHA_WEB_PORT"
  let logCfg = GameLog stderr
  ctx <- newAppCtx logCfg
  gsTVar <- newTVarIO initialGS
  let sctx = ServerCtx ctx gsTVar
  writeLog logCfg (ServerStart port)
  hPutStrLn stderr ("sasha-web server starting on port " <> show port)
  race_ (gameLoop ctx initialGS pg) (run port (app sctx))

readPort :: String -> Int
readPort s = fromMaybe 8081 (readMaybe s)
