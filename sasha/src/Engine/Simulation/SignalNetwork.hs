{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.SignalNetwork
  ( RhineM
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
import           Control.Monad.State (get, put, runStateT)
import           Control.Monad.Trans.Accum (AccumT, add, look, runAccumT)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import           Data.Functor.Identity (Identity, runIdentity)
import           Data.IORef (readIORef, writeIORef)
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
import           DSL.Builder
  ( WorldBuilderResult (WorldBuilderResult, resultCounters, resultGameState)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           Engine.Evaluators.Player.General (eval)
import           Engine.Simulation.Clocks (DSLTick, HeartbeatTick, PlayerTick)
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
  , Evaluator (Evaluator)
  , GameComputation (runGameComputation)
  , GameState
  , GameStateT (runGameStateT)
  , Narration (Narration, _actionConsequence, _actionEpilogue, _playerAction, _presenceListing)
  , NarrationMap (NarrationMap)
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
  , possibilityGraph
  , runEvaluator
  , sceneAgents
  , sceneMap
  , unNarrationMap
  , world
  )
import           Model.GID (GID)
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
  ( AppCtx (acBuilderCounters, acDSLChan, acInbound, acJoinChan, acKnownPlayers, acOutbound, acSessions)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingJoin, AwaitingSocket, InGame)
  , sessionGid
  )
import           Server.Validator (PlayerNameVAL, unPlayerNameVAL)

data JoinResult = NewPlayerJoined SessionId PlayerNameVAL (GID Agent)
                | ReturningPlayerJoined SessionId (GID Agent)

type RhineM :: Type -> Type
newtype RhineM a = RhineM { unRhineM :: AccumT (Last GameState) (ReaderT AppCtx IO) a }
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
askAppCtx = RhineM $ lift ask

gameLoop :: AppCtx -> GameState -> IO ()
gameLoop ctx gs =
  void (runReaderT (runAccumT (unRhineM (flow rhinePipeline)) (Last (Just gs))) ctx)

rhinePipeline :: Rhine RhineM
  (ParallelClock
    (ParallelClock
      (IOClock RhineM HeartbeatTick)
      (IOClock RhineM PlayerTick))
    (IOClock RhineM DSLTick)) () ()
rhinePipeline =
    (heartbeatSF @@ ioClock (waitClock :: HeartbeatTick)
     |@|
     playerTickBlock @@ ioClock (waitClock :: PlayerTick))
    |@|
    dslTickSF @@ ioClock (waitClock :: DSLTick)

heartbeatSF :: ClSF RhineM (IOClock RhineM HeartbeatTick) () ()
heartbeatSF = constMCl $ do
  appCtx <- askAppCtx
  liftIO $ do
    sessions <- readMVar (acSessions appCtx)
    let msg = SystemMessage "*** heartbeat"
    atomically $
      mapM_ (\sid -> writeTChan (acOutbound appCtx) (Routed sid msg))
        [sid | (sid, phase) <- assocs sessions, Just _ <- [sessionGid phase]]

dslTickSF :: ClSF RhineM (IOClock RhineM DSLTick) () ()
dslTickSF = constMCl $ do
  appCtx <- askAppCtx
  submissions <- liftIO $ drainChan (acDSLChan appCtx)
  when (not (null submissions)) $ do
    gs <- lookGameState
    counters <- liftIO $ readIORef (acBuilderCounters appCtx)
    let runSubmission prev dsl =
          runWorldBuilder (interpretDSL dsl)
            (initialBuilderState (resultGameState prev) (resultCounters prev))
        result = foldl' runSubmission (WorldBuilderResult gs counters) submissions
    liftIO $ writeIORef (acBuilderCounters appCtx) (resultCounters result)
    addGameState (resultGameState result)

playerTickBlock :: ClSF RhineM (IOClock RhineM PlayerTick) () ()
playerTickBlock = constMCl $ do
  gs <- lookGameState
  appCtx <- askAppCtx

  -- IO: gather inputs
  sessions <- liftIO $ readMVar (acSessions appCtx)
  known <- liftIO $ readMVar (acKnownPlayers appCtx)
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  msgs <- liftIO $ drainChan (acInbound appCtx)

  -- GENERATE: compose one big GameComputation
  let (pings, commandComp) = resolveCommands sessions msgs
      (joinResults, joinComp) = processJoinsPure known joins
      leavesComp = processLeavesPure sessions known
      tickComp = composeTick leavesComp joinComp commandComp (joinGIDs joinResults)

      -- EXECUTE: run once
      (result, gs') = runPureComputation tickComp gs

  -- IO: protocol replies (delivered regardless of tick result)
  liftIO . forM_ pings $ \sid ->
    atomically $ writeTChan (acOutbound appCtx) (Routed sid Pong)

  -- ERROR EVALUATION: after execution
  case result of
    Left err ->
      liftIO $ hPutStrLn stderr ("Tick computation failed: " <> unpack err)
    Right narrations -> do
      -- IO: execute join effects (session promotion, welcome messages)
      liftIO $ forM_ joinResults (executeJoinIO appCtx)
      -- IO: deliver narrations to clients
      liftIO $ deliverNarrationIO appCtx narrations

  addGameState gs'

composeTick :: GameComputation Identity ()
            -> GameComputation Identity ()
            -> GameComputation Identity ()
            -> [GID Agent]
            -> GameComputation Identity (Map (GID Agent) Narration)
composeTick leavesComp joinComp commandComp joinedGids = do
  leavesComp
  joinComp
  commandComp
  forM_ joinedGids $ \gid -> runEvalFor gid "look"
  extractNarration

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
      applyDeparture currentGs (sceneGid, scene, departed) =
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
  put (foldl' applyDeparture gs sceneDepartures)

processJoinsPure :: Map PlayerNameVAL (GID Agent)
                 -> [PlayerJoined]
                 -> ([JoinResult], GameComputation Identity ())
processJoinsPure known joins = (joinResults, mapM_ joinComputation joinResults)
  where
    joinResults = fmap classify joins
    classify (PlayerJoined sid name accountGid) =
      case lookup name known of
        Just gid -> ReturningPlayerJoined sid gid
        Nothing  -> NewPlayerJoined sid name accountGid
    joinComputation (ReturningPlayerJoined _sid gid) = do
      gs <- get
      case lookup gid (view (world . agentMap . getAgentMap) gs) of
        Nothing -> throwError ("Programmer Error: returning player agent not found: " <> pack (show gid))
        Just agent ->
          case lookup gid (view agentLocationMap gs) of
            Nothing -> throwError ("Programmer Error: returning player location not found: " <> pack (show gid))
            Just sceneGid ->
              case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
                Nothing -> throwError ("Programmer Error: returning player scene not found: " <> pack (show sceneGid))
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
      case view (possibilityGraph . newUserStartScene) gs of
        Nothing -> throwError "Programmer Error: world declared no newUser start scene"
        Just sceneGid ->
          case view (possibilityGraph . newUserMkAgent) gs of
            Nothing -> throwError "Programmer Error: world declared no newUser agent template"
            Just mkAgent ->
              case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
                Nothing -> throwError ("Programmer Error: new player start scene not found: " <> pack (show sceneGid))
                Just scene -> do
                  let agent = mkAgent (view unPlayerNameVAL name)
                      aMap = view (world . agentMap . getAgentMap) gs
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

joinGIDs :: [JoinResult] -> [GID Agent]
joinGIDs = fmap $ \case
  NewPlayerJoined _ _ gid       -> gid
  ReturningPlayerJoined _ gid -> gid

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
                   -> GameState
                   -> (Either Text a, GameState)
runPureComputation comp gs =
  runIdentity (runStateT (runGameStateT (runExceptT (runGameComputation comp))) gs)

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
      Just (SessionPhase n g (AwaitingJoin send)) -> insert sid (SessionPhase n g (InGame send)) sessions
      Just (SessionPhase _ _ AwaitingSocket)      -> sessions
      Just (SessionPhase _ _ (InGame _))          -> sessions
      Nothing                                     -> sessions
  atomically $
    writeTChan (acOutbound ctx)
      (Routed sid (ChatMessage ("Welcome, " <> view unPlayerNameVAL name <> "!")))
executeJoinIO ctx (ReturningPlayerJoined sid _gid) = do
  modifyMVar_ (acSessions ctx) $ \sessions ->
    pure $ case lookup sid sessions of
      Just (SessionPhase n g (AwaitingJoin send)) -> insert sid (SessionPhase n g (InGame send)) sessions
      Just (SessionPhase _ _ AwaitingSocket)      -> sessions
      Just (SessionPhase _ _ (InGame _))          -> sessions
      Nothing                                     -> sessions
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
