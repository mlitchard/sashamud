{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.EffectNetwork
  ( RhineM
  , JoinResult (..)
  , gameLoop
  ) where

import           SashaPrelude

import           API.Types
  ( MessageTo (GameCommand, Ping)
  , PlayerJoined (PlayerJoined)
  , Routed (Routed)
  , SessionId
  )
import           Control.Category ((>>>))
import           Control.Concurrent (modifyMVar_, readMVar)
import           Control.Concurrent.STM
  ( TChan
  , atomically
  , tryReadTChan
  , writeTChan
  )
import           Control.Monad.Except (runExceptT)
import           Control.Monad.Schedule.Class (MonadSchedule (schedule))
import           Control.Monad.State (runStateT)
import           Control.Monad.Trans.Accum (AccumT, add, look, runAccumT)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import           Data.Functor.Identity (runIdentity)
import           Data.IORef (atomicModifyIORef')
import           Data.Map.Strict
  ( Map
  , assocs
  , elems
  , fromList
  , insert
  , keys
  , lookup
  , unionWith
  )
import           Data.Monoid (Last (Last))
import qualified Data.Set as Set
  ( delete
  , filter
  , fromList
  , insert
  , member
  , null
  , toList
  )
import           Engine.Evaluators.Player.General (eval)
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
import           Grammar.Lexer (lexify, tokens)
import           Grammar.Sentence (parseTokens)
import           Lens.Micro.Platform (at, over, set, view, (?~))
import           Model.Core
  ( ActionManagementFunctions (ActionManagementFunctions)
  , Agent (..)
  , AgentKind (Denizen)
  , ComputationContext (ComputationContext, _ctxPossibilityGraph)
  , Evaluator (Evaluator)
  , GameComputation (runGameComputation)
  , GameState
  , GameStateT (runGameStateT)
  , Narration (Narration, _actionConsequence, _actionEpilogue, _playerAction, _presenceListing)
  , NarrationMap (NarrationMap)
  , PossibilityGraph
  , agentKind
  , agentLocationMap
  , agentMap
  , agentShortName
  , evaluation
  , getAgentMap
  , getGIDToDataMap
  , narrationMap
  , runEvaluator
  , sceneAgents
  , sceneMap
  , unNarrationMap
  , world
  )
import           Model.GID (GID (GID))
import           Model.RichText (TextColor (White), colored, plain, toPlainText)
import           Model.WireProtocol
  ( MessageFrom (ChatMessage, GameNarration, Pong, SystemMessage)
  )
import           Server.App
  ( AppCtx (acInbound, acJoinChan, acKnownPlayers, acNextAgentId, acOutbound, acPlayerMap)
  , succPInt
  , unPInt
  )
import           Server.Validator (PlayerNameVAL, unPlayerNameVAL)

data JoinResult = NewPlayerJoined SessionId PlayerNameVAL (GID Agent)
                | ReturningPlayerJoined SessionId PlayerNameVAL (GID Agent)

data JoinFailure
  = ReturningAgentMissing
  | ReturningLocationMissing
  | ReturningSceneMissing

data JoinError = JoinError SessionId JoinFailure

joinFailureText :: JoinFailure -> Text
joinFailureText ReturningAgentMissing    = "returning player agent not found"
joinFailureText ReturningLocationMissing = "returning player location not found"
joinFailureText ReturningSceneMissing    = "returning player scene not found"

type RhineM :: Type -> Type
newtype RhineM a = RhineM { unRhineM :: AccumT (Last GameState) (ReaderT PossibilityGraph (ReaderT AppCtx IO)) a }
  deriving newtype (Applicative, Functor, Monad, MonadIO)

instance MonadSchedule RhineM where
  schedule = fmap unRhineM >>> schedule >>> fmap (fmap (fmap RhineM)) >>> RhineM

lookGameState :: RhineM GameState
lookGameState = RhineM $ do
  Last mgs <- look
  case mgs of
    Nothing -> error "lookGameState: game state not initialized"
    Just gs -> pure gs

addGameState :: GameState -> RhineM ()
addGameState gs = RhineM $ add (Last (Just gs))

askAppCtx :: RhineM AppCtx
askAppCtx = RhineM $ lift (lift ask)

askPossibilityGraph :: RhineM PossibilityGraph
askPossibilityGraph = RhineM $ lift ask

gameLoop :: AppCtx -> GameState -> PossibilityGraph -> IO ()
gameLoop ctx gs pg =
  void (runReaderT (runReaderT (runAccumT (unRhineM (flow rhinePipeline)) (Last (Just gs))) pg) ctx)

rhinePipeline :: Rhine RhineM
  (ParallelClock
    (IOClock RhineM HeartbeatTick)
    (IOClock RhineM PlayerTick)) () ()
rhinePipeline =
    heartbeatSF @@ ioClock (waitClock :: HeartbeatTick)
    |@|
    (deliverNarrationSF >-> processLeavesSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF)
      @@ ioClock (waitClock :: PlayerTick)

heartbeatSF :: ClSF RhineM (IOClock RhineM HeartbeatTick) () ()
heartbeatSF = constMCl $ do
  appCtx <- askAppCtx
  liftIO $ do
    pMap <- readMVar (acPlayerMap appCtx)
    let msg = SystemMessage "*** heartbeat"
    atomically $
      mapM_ (\sid -> writeTChan (acOutbound appCtx) (Routed sid msg))
        (keys pMap)

deliverNarrationSF :: ClSF RhineM (IOClock RhineM PlayerTick) () (Map SessionId (GID Agent))
deliverNarrationSF = constMCl $ do
  appCtx <- askAppCtx
  gs <- lookGameState
  pMap <- liftIO $ readMVar (acPlayerMap appCtx)
  let nMap = view (narrationMap . unNarrationMap) gs
  forM_ (assocs nMap) $ \(agentGid, narr) -> do
    let targetSids = [s | (s, g) <- assocs pMap, g == agentGid]
    forM_ targetSids $ \targetSid ->
      liftIO . atomically $
        writeTChan (acOutbound appCtx) (Routed targetSid (GameNarration narr))
  when (not (null nMap)) $
    addGameState (set narrationMap (NarrationMap mempty) gs)
  pure pMap

processLeavesSF :: ClSF RhineM (IOClock RhineM PlayerTick) (Map SessionId (GID Agent)) (Map PlayerNameVAL (GID Agent))
processLeavesSF = arrMCl $ \pMap -> do
  appCtx <- askAppCtx
  gs <- lookGameState
  known <- liftIO $ readMVar (acKnownPlayers appCtx)
  let activeGids = Set.fromList (elems pMap)
      knownGids = Set.fromList (elems known)
      aMap = view (world . agentMap . getAgentMap) gs
      isDeparted gid = Set.member gid knownGids
                    && not (Set.member gid activeGids)
      sceneDepartures =
        [ (sceneGid, scene, departed)
        | (sceneGid, scene) <- assocs (view (world . sceneMap . getGIDToDataMap) gs)
        , let departed = Set.filter isDeparted (view sceneAgents scene)
        , not (Set.null departed)
        ]
  forM_ sceneDepartures $ \(sceneGid, scene, departed) -> do
    currentGs <- lookGameState
    let remaining = foldl' (flip Set.delete) (view sceneAgents scene) (toList departed)
        scene' = set sceneAgents remaining scene
        recipientGids = [g | g <- Set.toList remaining
                           , Just a <- [lookup g aMap]
                           , view agentKind a == Denizen]
        departNarr = mconcat
          [ Narration
              { _playerAction      = []
              , _actionConsequence = [view agentShortName a <> plain " has departed."]
              , _presenceListing   = []
              , _actionEpilogue    = []
              }
          | gid <- Set.toList departed
          , Just a <- [lookup gid aMap]
          ]
        narrations = fromList [(r, departNarr) | r <- recipientGids]
        gs' = currentGs
          & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
          & over (narrationMap . unNarrationMap) (unionWith (<>) narrations)
    addGameState gs'
  pure known

processJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) (Map PlayerNameVAL (GID Agent)) [Either JoinError JoinResult]
processJoinsSF = arrMCl $ \known -> do
  appCtx <- askAppCtx
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  traverse (processOneJoin known) joins

executeJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) [Either JoinError JoinResult] ()
executeJoinsSF = arrMCl $ \results -> do
  appCtx <- askAppCtx
  liftIO . forM_ results $ \case
    Left (JoinError sid failure) ->
      atomically $ writeTChan (acOutbound appCtx) (Routed sid (SystemMessage (joinFailureText failure)))
    Right joinResult ->
      executeJoin appCtx joinResult

processOneJoin :: Map PlayerNameVAL (GID Agent) -> PlayerJoined -> RhineM (Either JoinError JoinResult)
processOneJoin known (PlayerJoined sid name) =
  case lookup name known of
    Just gid -> do
      gs <- lookGameState
      case lookup gid (view (world . agentMap . getAgentMap) gs) of
        Nothing -> pure (Left (JoinError sid ReturningAgentMissing))
        Just agent ->
          case lookup gid (view agentLocationMap gs) of
            Nothing -> pure (Left (JoinError sid ReturningLocationMissing))
            Just sceneGid ->
              case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
                Nothing -> pure (Left (JoinError sid ReturningSceneMissing))
                Just scene -> do
                  let aMap = view (world . agentMap . getAgentMap) gs
                      scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
                      announceNarration = Narration
                        { _playerAction      = []
                        , _actionConsequence = [colored White (toPlainText (view agentShortName agent) <> " has arrived.")]
                        , _presenceListing   = []
                        , _actionEpilogue    = []
                        }
                      recipientGids = [g | g <- Set.toList (view sceneAgents scene')
                                         , g /= gid
                                         , Just a <- [lookup g aMap]
                                         , view agentKind a == Denizen]
                      joinNarrations = fromList [(g, announceNarration) | g <- recipientGids]
                      gs' = gs
                        & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
                        & over (narrationMap . unNarrationMap) (unionWith (<>) joinNarrations)
                  addGameState gs'
                  pure (Right (ReturningPlayerJoined sid name gid))
    Nothing -> do
      gs <- lookGameState
      appCtx <- askAppCtx
      nextId <- liftIO $ atomicModifyIORef' (acNextAgentId appCtx) (\p -> (succPInt p, p))
      let gid = GID (unPInt nextId)
          lobbyGid = GID 0
          agent = mkDenizen name
          aMap = view (world . agentMap . getAgentMap) gs
          lobby = fromMaybe
            (error "processOneJoin: lobby scene (GID 0) not found — game state is broken")
            (lookup lobbyGid (view (world . sceneMap . getGIDToDataMap) gs))
          lobby' = set sceneAgents (Set.insert gid (view sceneAgents lobby)) lobby
          announceNarration = Narration
            { _playerAction      = []
            , _actionConsequence = [colored White (view unPlayerNameVAL name <> " has arrived.")]
            , _presenceListing   = []
            , _actionEpilogue    = []
            }
          recipientGids = [g | g <- Set.toList (view sceneAgents lobby)
                              , Just a <- [lookup g aMap]
                              , view agentKind a == Denizen]
          joinNarrations = fromList [(g, announceNarration) | g <- recipientGids]
          gs' = gs
            & world . agentMap . getAgentMap . at gid ?~ agent
            & world . sceneMap . getGIDToDataMap . at lobbyGid ?~ lobby'
            & over (narrationMap . unNarrationMap) (unionWith (<>) joinNarrations)
            & evaluation . at gid ?~ Evaluator eval
            & agentLocationMap . at gid ?~ lobbyGid
      addGameState gs'
      pure (Right (NewPlayerJoined sid name gid))

mkDenizen :: PlayerNameVAL -> Agent
mkDenizen name = Agent
  { _agentShortName        = plain (view unPlayerNameVAL name)
  , _agentDescription      = colored White "A newly arrived adventurer."
  , _agentTitle            = mempty
  , _agentActionManagement = ActionManagementFunctions mempty
  , _agentKind             = Denizen
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
  appCtx <- askAppCtx
  liftIO $ drainChan (acInbound appCtx)

processInputSF :: ClSF RhineM (IOClock RhineM PlayerTick) [Routed MessageTo] ()
processInputSF = arrMCl $ \msgs -> do
  appCtx <- askAppCtx
  pg     <- askPossibilityGraph
  pMap   <- liftIO $ readMVar (acPlayerMap appCtx)
  forM_ msgs $ \(Routed sid msgTo) ->
    case msgTo of
      Ping ->
        liftIO . atomically $
          writeTChan (acOutbound appCtx) (Routed sid Pong)
      GameCommand cmdText -> do
        gs <- lookGameState
        case lookup sid pMap of
          Nothing  -> pure ()
          Just gid ->
            case lexify tokens cmdText of
              Left err ->
                liftIO . atomically $
                  writeTChan (acOutbound appCtx) (Routed sid (SystemMessage err))
              Right lexemes ->
                case parseTokens lexemes of
                  Left err ->
                    liftIO . atomically $
                      writeTChan (acOutbound appCtx) (Routed sid (SystemMessage err))
                  Right sentence -> do
                    case lookup gid (view evaluation gs) of
                      Nothing ->
                        liftIO . atomically $
                          writeTChan (acOutbound appCtx) (Routed sid (SystemMessage "failure to load evaluator"))
                      Just evaluator -> do
                        let ctx = ComputationContext { _ctxPossibilityGraph = pg }
                            comp = view runEvaluator evaluator gid sentence
                            result = runIdentity
                                   . flip runStateT gs
                                   . runGameStateT
                                   . runExceptT
                                   . flip runReaderT ctx
                                   . runGameComputation
                                   $ comp
                        case result of
                          (Left err, _) ->
                            liftIO . atomically $
                              writeTChan (acOutbound appCtx) (Routed sid (SystemMessage err))
                          (Right (), gs') ->
                            addGameState gs'

drainChan :: TChan a -> IO [a]
drainChan chan = do
  mMsg <- atomically (tryReadTChan chan)
  case mMsg of
    Nothing -> pure []
    Just m  -> (m :) <$> drainChan chan
