{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.EffectNetwork
  ( WorldAccum (..)
  , JoinResult (..)
  , RhineM
  , gameLoop
  ) where

import           SashaPrelude

import           API.Types
  ( MessageTo (GameCommand, Ping)
  , PlayerJoined (PlayerJoined)
  , Routed (Routed)
  , SessionId
  )
import           Control.Concurrent (modifyMVar_, readMVar)
import           Control.Concurrent.STM
  ( TChan
  , atomically
  , tryReadTChan
  , writeTChan
  )
import           Control.Monad.Trans.Accum (AccumT, add, look, runAccumT)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import           Data.Map.Strict
  ( Map
  , assocs
  , elems
  , insert
  , keys
  , lookup
  , singleton
  )
import           Data.Ord (max)
import           Data.Set (Set)
import qualified Data.Set as Set
  ( delete
  , filter
  , fromList
  , insert
  , member
  , null
  )
import           Engine.Simulation.Clocks (HeartbeatTick, PlayerTick)
import           FRP.Rhine
  ( ClSF
  , IOClock
  , ParallelClock
  , Rhine
  , arrMCl
  , constMCl
  , flow
  , ioClock
  , waitClock
  , (>->)
  , (@@)
  , (|@|)
  )
import           Lens.Micro.Platform (set, view)
import           Model.Core
  ( Agent (..)
  , AgentKind (PlayerAgent)
  , GameState
  , Object
  , PerceptionMap (PerceptionMap)
  , PossibilityGraph
  , Scene
  , SpatialRelationshipMap (SpatialRelationshipMap)
  , agentCurrentScene
  , agentKind
  , agentMap
  , agentShortName
  , defaultActionManagement
  , getAgentMap
  , getGIDToDataMap
  , globalSemanticMap
  , objectMap
  , perceptionMap
  , sceneAgents
  , sceneMap
  , spatialRelationshipMap
  , world
  )
import           Model.GID (GID (GID))
import           Model.RichText (TextColor (White), colored)
import           Model.WireProtocol
  ( MessageFrom (ChatMessage, Pong, SystemMessage)
  )
import           Server.App
  ( AppCtx (acInbound, acJoinChan, acKnownPlayers, acOutbound, acPlayerMap)
  )
import           Server.Validator (PlayerNameVAL, unPlayerNameVAL)

data WorldAccum = WorldAccum
  { waAgentMap               :: Map (GID Agent) Agent
  , waSceneMap               :: Map (GID Scene) Scene
  , waObjectMap              :: Map (GID Object) Object
  , waSpatialRelationshipMap :: SpatialRelationshipMap
  , waGlobalSemanticMap      :: Map Text (Set (GID Object))
  , waPerceptionMap          :: PerceptionMap
  , waNextAgentId            :: Int
  }

instance Semigroup WorldAccum where
  wa1 <> wa2 = WorldAccum
    { waAgentMap               = waAgentMap wa2 <> waAgentMap wa1
    , waSceneMap               = waSceneMap wa2 <> waSceneMap wa1
    , waObjectMap              = waObjectMap wa2 <> waObjectMap wa1
    , waSpatialRelationshipMap = waSpatialRelationshipMap wa2
    , waGlobalSemanticMap      = waGlobalSemanticMap wa2 <> waGlobalSemanticMap wa1
    , waPerceptionMap          = waPerceptionMap wa2
    , waNextAgentId            = max (waNextAgentId wa1) (waNextAgentId wa2)
    }

instance Monoid WorldAccum where
  mempty = WorldAccum mempty mempty mempty SpatialRelationshipMap mempty PerceptionMap 0

data JoinResult = NewPlayerJoined SessionId PlayerNameVAL (GID Agent)
                | ReturningPlayerJoined SessionId PlayerNameVAL (GID Agent)

type RhineM :: Type -> Type
type RhineM =
  AccumT WorldAccum
    (ReaderT PossibilityGraph
      (ReaderT AppCtx IO))

gameLoop :: AppCtx -> GameState -> PossibilityGraph -> IO ()
gameLoop ctx gs pg =
  let iw = view world gs
      initAccum = WorldAccum
        { waAgentMap               = view (agentMap . getAgentMap) iw
        , waSceneMap               = view (sceneMap . getGIDToDataMap) iw
        , waObjectMap              = view (objectMap . getGIDToDataMap) iw
        , waSpatialRelationshipMap = view spatialRelationshipMap iw
        , waGlobalSemanticMap      = view globalSemanticMap iw
        , waPerceptionMap          = view perceptionMap iw
        , waNextAgentId            = 1000
        }
  in void (runReaderT
    (runReaderT
      (runAccumT (flow rhinePipeline) initAccum)
      pg)
    ctx)

rhinePipeline :: Rhine RhineM
  (ParallelClock
    (ParallelClock
      (IOClock RhineM HeartbeatTick)
      (IOClock RhineM PlayerTick))
    (IOClock RhineM PlayerTick)) () ()
rhinePipeline =
      (heartbeatSF
          @@ ioClock (waitClock :: HeartbeatTick)
    |@| (processJoinsSF >-> executeJoinsSF >-> processLeavesSF)
          @@ ioClock (waitClock :: PlayerTick))
    |@| (gatherInputSF >-> processInputSF)
          @@ ioClock (waitClock :: PlayerTick)

heartbeatSF :: ClSF RhineM (IOClock RhineM HeartbeatTick) () ()
heartbeatSF = constMCl $ do
  appCtx <- lift (lift ask)
  liftIO $ do
    pMap <- readMVar (acPlayerMap appCtx)
    let msg = SystemMessage "*** heartbeat"
    atomically $
      mapM_ (\sid -> writeTChan (acOutbound appCtx) (Routed sid msg))
        (keys pMap)

processJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) () [JoinResult]
processJoinsSF = constMCl $ do
  appCtx <- lift (lift ask)
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  known <- liftIO $ readMVar (acKnownPlayers appCtx)
  traverse (processOneJoin known) joins

executeJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) [JoinResult] ()
executeJoinsSF = arrMCl $ \results -> do
  appCtx <- lift (lift ask)
  liftIO $ mapM_ (executeJoin appCtx) results

processLeavesSF :: ClSF RhineM (IOClock RhineM PlayerTick) () ()
processLeavesSF = constMCl $ do
  appCtx <- lift (lift ask)
  wa <- look
  pMap <- liftIO $ readMVar (acPlayerMap appCtx)
  let activeGids = Set.fromList (elems pMap)
  forM_ (assocs (waSceneMap wa)) $ \(sceneGid, scene) -> do
    let agents = view sceneAgents scene
        isDeparted gid = case lookup gid (waAgentMap wa) of
          Just agent -> view agentKind agent == PlayerAgent
                     && not (Set.member gid activeGids)
          Nothing    -> False
        departed = Set.filter isDeparted agents
    when (not (Set.null departed)) $ do
      let scene' = set sceneAgents (foldl' (flip Set.delete) agents (toList departed)) scene
          witnessSids = [sid | (sid, gid) <- assocs pMap, Set.member gid agents]
      add mempty { waSceneMap = singleton sceneGid scene' }
      forM_ (toList departed) $ \gid ->
        case lookup gid (waAgentMap wa) of
          Nothing -> pure ()
          Just agent -> do
            let name = view agentShortName agent
                msg = SystemMessage ("*** " <> name <> " has departed")
            liftIO . atomically $
              mapM_ (\sid -> writeTChan (acOutbound appCtx) (Routed sid msg))
                witnessSids

processOneJoin :: Map PlayerNameVAL (GID Agent) -> PlayerJoined -> RhineM JoinResult
processOneJoin known (PlayerJoined sid name) =
  case lookup name known of
    Just gid -> do
      wa <- look
      case lookup gid (waAgentMap wa) of
        Nothing -> pure ()
        Just agent -> do
          let sceneGid = view agentCurrentScene agent
          case lookup sceneGid (waSceneMap wa) of
            Nothing -> pure ()
            Just scene -> do
              let scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
              add mempty { waSceneMap = singleton sceneGid scene' }
      pure (ReturningPlayerJoined sid name gid)
    Nothing -> do
      wa <- look
      let nextId = waNextAgentId wa
          gid = GID nextId
          lobbyGid = GID 0
          agent = mkPlayerAgent name lobbyGid
          lobby = fromMaybe
            (error "processOneJoin: lobby scene (GID 0) not found — game state is broken")
            (lookup lobbyGid (waSceneMap wa))
          lobby' = set sceneAgents (Set.insert gid (view sceneAgents lobby)) lobby
      add WorldAccum
        { waAgentMap               = singleton gid agent
        , waSceneMap               = singleton lobbyGid lobby'
        , waObjectMap              = mempty
        , waSpatialRelationshipMap = SpatialRelationshipMap
        , waGlobalSemanticMap      = mempty
        , waPerceptionMap          = PerceptionMap
        , waNextAgentId            = nextId + 1
        }
      pure (NewPlayerJoined sid name gid)

mkPlayerAgent :: PlayerNameVAL -> GID Scene -> Agent
mkPlayerAgent name sceneGid = Agent
  { _agentShortName        = view unPlayerNameVAL name
  , _agentDescription      = colored White "A newly arrived adventurer."
  , _agentTitle            = ""
  , _agentActionManagement = defaultActionManagement
  , _agentCurrentScene     = sceneGid
  , _agentKind             = PlayerAgent
  }

executeJoin :: AppCtx -> JoinResult -> IO ()
executeJoin ctx (NewPlayerJoined sid name gid) = do
  modifyMVar_ (acKnownPlayers ctx) (pure . insert name gid)
  modifyMVar_ (acPlayerMap ctx) (pure . insert sid gid)
  atomically $
    writeTChan (acOutbound ctx)
      (Routed sid (ChatMessage ("Welcome, " <> view unPlayerNameVAL name <> "!")))
executeJoin ctx (ReturningPlayerJoined sid _name gid) = do
  modifyMVar_ (acPlayerMap ctx) (pure . insert sid gid)
  atomically $
    writeTChan (acOutbound ctx)
      (Routed sid (ChatMessage "Welcome back!"))

gatherInputSF :: ClSF RhineM (IOClock RhineM PlayerTick) () [Routed MessageTo]
gatherInputSF = constMCl $ do
  appCtx <- lift (lift ask)
  liftIO $ drainChan (acInbound appCtx)

processInputSF :: ClSF RhineM (IOClock RhineM PlayerTick) [Routed MessageTo] ()
processInputSF = arrMCl $ \msgs -> do
  appCtx <- lift (lift ask)
  forM_ msgs $ \(Routed sid msgTo) ->
    case msgTo of
      Ping ->
        liftIO . atomically $
          writeTChan (acOutbound appCtx) (Routed sid Pong)
      GameCommand _ ->
        pure ()

drainChan :: TChan a -> IO [a]
drainChan chan = do
  mMsg <- atomically (tryReadTChan chan)
  case mMsg of
    Nothing -> pure []
    Just m  -> (m :) <$> drainChan chan

