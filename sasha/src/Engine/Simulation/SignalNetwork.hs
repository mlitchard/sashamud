{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.SignalNetwork
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
import           Control.Monad.Except (runExceptT, throwError)
import           Control.Monad.Schedule.Class (MonadSchedule (schedule))
import           Control.Monad.State (get, modify, put, runStateT)
import           Control.Monad.Trans.Accum (AccumT, add, look, runAccumT)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import           Data.Functor.Identity (Identity, runIdentity)
import           Data.IORef (atomicModifyIORef')
import           Data.Map.Strict
  ( Map
  , assocs
  , elems
  , fromList
  , insert
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
  , constMCl
  , flow
  , ioClock
  , waitClock
  , (@@)
  , (|@|)
  )
import           Grammar.Lexer (lexify, tokens)
import           Grammar.Sentence (parseTokens)
import           Lens.Micro.Platform (at, over, set, use, view, (.=), (?~))
import           Model.Core
  ( Agent
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
  , newUserMkAgent
  , newUserStartScene
  , runEvaluator
  , sceneAgents
  , sceneMap
  , unNarrationMap
  , world
  )
import           Model.GID (GID (GID))
import           Model.RichText
  ( RichText
  , TextColor (White)
  , colored
  , plain
  , toPlainText
  )
import           Model.WireProtocol
  ( MessageFrom (ChatMessage, GameNarration, Pong, SystemMessage)
  )
import           Server.App
  ( AppCtx (acInbound, acJoinChan, acKnownPlayers, acNextAgentId, acOutbound, acSessions)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingJoin, AwaitingSocket, InGame)
  , sessionGid
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
  | NewUserSceneMissing

joinFailureText :: JoinFailure -> Text
joinFailureText ReturningAgentMissing    = "returning player agent not found"
joinFailureText ReturningLocationMissing = "returning player location not found"
joinFailureText ReturningSceneMissing    = "returning player scene not found"
joinFailureText NewUserSceneMissing      = "new player start scene not found"

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
    playerTickBlock @@ ioClock (waitClock :: PlayerTick)

heartbeatSF :: ClSF RhineM (IOClock RhineM HeartbeatTick) () ()
heartbeatSF = constMCl $ do
  appCtx <- askAppCtx
  liftIO $ do
    sessions <- readMVar (acSessions appCtx)
    let msg = SystemMessage "*** heartbeat"
    atomically $
      mapM_ (\sid -> writeTChan (acOutbound appCtx) (Routed sid msg))
        [sid | (sid, phase) <- assocs sessions, Just _ <- [sessionGid phase]]

playerTickBlock :: ClSF RhineM (IOClock RhineM PlayerTick) () ()
playerTickBlock = constMCl $ do
  gs <- lookGameState
  appCtx <- askAppCtx
  pg <- askPossibilityGraph

  -- IO: gather inputs
  sessions <- liftIO $ readMVar (acSessions appCtx)
  known <- liftIO $ readMVar (acKnownPlayers appCtx)
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  msgs <- liftIO $ drainChan (acInbound appCtx)

  -- IO: pre-allocate GIDs for new players
  newGIDs <- liftIO $ allocateNewGIDs appCtx known joins

  -- GENERATE: compose one big GameComputation
  let (pings, commandComp) = resolveCommands sessions msgs
      ctx = ComputationContext { _ctxPossibilityGraph = pg }
      tickComp = composeTick sessions known newGIDs commandComp pg

      -- EXECUTE: run once
      (result, gs') = runPureComputation tickComp ctx gs

  -- IO: protocol replies (delivered regardless of tick result)
  liftIO . forM_ pings $ \sid ->
    atomically $ writeTChan (acOutbound appCtx) (Routed sid Pong)

  -- ERROR EVALUATION: after execution
  case result of
    Left err ->
      liftIO $ hPutStrLn stderr ("Tick computation failed: " <> unpack err)
    Right (joinResults, narrations) -> do
      -- IO: execute join effects (session promotion, welcome messages)
      liftIO $ forM_ joinResults (executeJoinIO appCtx)
      -- IO: deliver narrations to clients
      liftIO $ deliverNarrationIO appCtx narrations

  addGameState gs'

composeTick :: Map SessionId SessionPhase
            -> Map PlayerNameVAL (GID Agent)
            -> [(PlayerJoined, GID Agent)]
            -> GameComputation Identity ()
            -> PossibilityGraph
            -> GameComputation Identity ([JoinResult], Map (GID Agent) Narration)
composeTick sessions known newGIDs commandComp pg = do
  processLeavesPure sessions known
  let (joinResults, joinComp) = processJoinsPure known newGIDs pg
  joinComp
  commandComp
  forM_ (successfulJoinGIDs joinResults) $ \gid -> runEvalFor gid "look"
  narrations <- extractNarration
  pure (joinResults, narrations)

processLeavesPure :: Map SessionId SessionPhase
                  -> Map PlayerNameVAL (GID Agent)
                  -> GameComputation Identity ()
processLeavesPure sessions known = do
  gs <- get
  let activeGids = Set.fromList [gid | phase <- elems sessions, Just gid <- [sessionGid phase]]
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
  forM_ sceneDepartures $ \(sceneGid, scene, departed) ->
    modify $ \currentGs ->
      let remaining = foldl' (flip Set.delete) (view sceneAgents scene) (toList departed)
          scene' = set sceneAgents remaining scene
          departNarr = mconcat
            [ consequenceNarration (view agentShortName a <> plain " has departed.")
            | gid <- Set.toList departed
            , Just a <- [lookup gid aMap]
            ]
      in currentGs
           & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
           & announceToDenizens aMap (Set.toList remaining) departNarr

processJoinsPure :: Map PlayerNameVAL (GID Agent)
                 -> [(PlayerJoined, GID Agent)]
                 -> PossibilityGraph
                 -> ([JoinResult], GameComputation Identity ())
processJoinsPure known newGIDs pg = (joinResults, mapM_ joinComputation joinResults)
  where
    joinResults = fmap classify newGIDs
    classify (PlayerJoined sid name, allocatedGid) =
      case lookup name known of
        Just gid -> ReturningPlayerJoined sid name gid
        Nothing  -> NewPlayerJoined sid name allocatedGid
    joinComputation (ReturningPlayerJoined _sid _name gid) = do
      gs <- get
      case lookup gid (view (world . agentMap . getAgentMap) gs) of
        Nothing -> throwError (joinFailureText ReturningAgentMissing)
        Just agent ->
          case lookup gid (view agentLocationMap gs) of
            Nothing -> throwError (joinFailureText ReturningLocationMissing)
            Just sceneGid ->
              case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
                Nothing -> throwError (joinFailureText ReturningSceneMissing)
                Just scene -> do
                  let aMap = view (world . agentMap . getAgentMap) gs
                      scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
                      announceNarration = consequenceNarration (colored White (toPlainText (view agentShortName agent) <> " has arrived."))
                      others = [g | g <- Set.toList (view sceneAgents scene'), g /= gid]
                      gs' = gs
                        & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
                        & announceToDenizens aMap others announceNarration
                  put gs'
    joinComputation (NewPlayerJoined _sid name gid) = do
      gs <- get
      let sceneGid = view newUserStartScene pg
          mkAgent = view newUserMkAgent pg
          agent = mkAgent (view unPlayerNameVAL name)
      case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
        Nothing -> throwError (joinFailureText NewUserSceneMissing)
        Just scene -> do
          let aMap = view (world . agentMap . getAgentMap) gs
              scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
              announceNarration = consequenceNarration (colored White (view unPlayerNameVAL name <> " has arrived."))
              others = [g | g <- Set.toList (view sceneAgents scene'), g /= gid]
              gs' = gs
                & world . agentMap . getAgentMap . at gid ?~ agent
                & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
                & agentLocationMap . at gid ?~ sceneGid
                & announceToDenizens aMap others announceNarration
                & evaluation . at gid ?~ Evaluator eval
          put gs'

consequenceNarration :: RichText -> Narration
consequenceNarration line = Narration
  { _playerAction      = []
  , _actionConsequence = [line]
  , _presenceListing   = []
  , _actionEpilogue    = []
  }

announceToDenizens :: Map (GID Agent) Agent -> [GID Agent] -> Narration -> GameState -> GameState
announceToDenizens aMap gids narr =
  let recipients = [g | g <- gids, Just a <- [lookup g aMap], view agentKind a == Denizen]
  in over (narrationMap . unNarrationMap) (flip (unionWith (<>)) (fromList [(g, narr) | g <- recipients]))

extractNarration :: GameComputation Identity (Map (GID Agent) Narration)
extractNarration = do
  nMap <- use (narrationMap . unNarrationMap)
  narrationMap .= NarrationMap mempty
  pure nMap

successfulJoinGIDs :: [JoinResult] -> [GID Agent]
successfulJoinGIDs = fmap $ \case
  NewPlayerJoined _ _ gid       -> gid
  ReturningPlayerJoined _ _ gid -> gid

runEvalFor :: GID Agent -> Text -> GameComputation Identity ()
runEvalFor gid cmdText =
  case lexify tokens cmdText of
    Left err -> throwError err
    Right lexemes ->
      case parseTokens lexemes of
        Left err -> throwError err
        Right sentence -> do
          evaluator <- lookupEvaluatorOrThrow gid
          view runEvaluator evaluator gid sentence

lookupEvaluatorOrThrow :: GID Agent -> GameComputation Identity Evaluator
lookupEvaluatorOrThrow gid = do
  evals <- use evaluation
  case lookup gid evals of
    Nothing        -> throwError ("Programmer Error: no evaluator for " <> pack (show gid))
    Just evaluator -> pure evaluator

runPureComputation :: GameComputation Identity a
                   -> ComputationContext
                   -> GameState
                   -> (Either Text a, GameState)
runPureComputation comp ctx gs =
  runIdentity (runStateT (runGameStateT (runExceptT (runReaderT (runGameComputation comp) ctx))) gs)

allocateNewGIDs :: AppCtx
                -> Map PlayerNameVAL (GID Agent)
                -> [PlayerJoined]
                -> IO [(PlayerJoined, GID Agent)]
allocateNewGIDs appCtx known joins =
  forM joins $ \joined@(PlayerJoined _ name) ->
    case lookup name known of
      Just gid -> pure (joined, gid)
      Nothing -> do
        nextId <- atomicModifyIORef' (acNextAgentId appCtx) (\p -> (succPInt p, p))
        pure (joined, GID (unPInt nextId))

resolveCommands :: Map SessionId SessionPhase
                -> [Routed MessageTo]
                -> ([SessionId], GameComputation Identity ())
resolveCommands sessions msgs = (pings, mapM_ commandComputation cmds)
  where
    pings = [sid | Routed sid Ping <- msgs]
    cmds  = [(sid, cmdText) | Routed sid (GameCommand cmdText) <- msgs]
    commandComputation (sid, cmdText) =
      case lookup sid sessions >>= sessionGid of
        Nothing  -> throwError ("Programmer Error: no InGame session for " <> pack (show sid))
        Just gid -> runEvalFor gid cmdText

executeJoinIO :: AppCtx -> JoinResult -> IO ()
executeJoinIO ctx (NewPlayerJoined sid name gid) = do
  modifyMVar_ (acKnownPlayers ctx) (pure . insert name gid)
  modifyMVar_ (acSessions ctx) $ \sessions ->
    pure $ case lookup sid sessions of
      Just (SessionPhase n (AwaitingJoin send)) -> insert sid (SessionPhase n (InGame send gid)) sessions
      Just (SessionPhase _ AwaitingSocket)      -> sessions
      Just (SessionPhase _ (InGame _ _))        -> sessions
      Nothing                                   -> sessions
  atomically $
    writeTChan (acOutbound ctx)
      (Routed sid (ChatMessage ("Welcome, " <> view unPlayerNameVAL name <> "!")))
executeJoinIO ctx (ReturningPlayerJoined sid _name gid) = do
  modifyMVar_ (acSessions ctx) $ \sessions ->
    pure $ case lookup sid sessions of
      Just (SessionPhase n (AwaitingJoin send)) -> insert sid (SessionPhase n (InGame send gid)) sessions
      Just (SessionPhase _ AwaitingSocket)      -> sessions
      Just (SessionPhase _ (InGame _ _))        -> sessions
      Nothing                                   -> sessions
  atomically $
    writeTChan (acOutbound ctx)
      (Routed sid (ChatMessage "Welcome back!"))

deliverNarrationIO :: AppCtx
                   -> Map (GID Agent) Narration
                   -> IO ()
deliverNarrationIO appCtx narrations = do
  sessions <- readMVar (acSessions appCtx)
  forM_ (assocs narrations) $ \(agentGid, narr) -> do
    let targetSids = [s | (s, phase) <- assocs sessions, sessionGid phase == Just agentGid]
    forM_ targetSids $ \targetSid ->
      atomically $ writeTChan (acOutbound appCtx) (Routed targetSid (GameNarration narr))

drainChan :: TChan a -> IO [a]
drainChan chan = do
  mMsg <- atomically (tryReadTChan chan)
  case mMsg of
    Nothing -> pure []
    Just m  -> (m :) <$> drainChan chan
