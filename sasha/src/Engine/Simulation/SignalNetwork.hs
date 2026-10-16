{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.SignalNetwork
  ( RhineM
  , gameLoop
  , insertRepairFailure
  , insertRepairSuccess
  ) where

import           SashaPrelude

import           API.Types
  ( AuthenticatedUser
  , MessageTo (GameCommand, Ping, RepairedCommand)
  , ParseFailure (ParseFailure)
  , PlayerJoined (PlayerJoined)
  , RepairAttempt (RepairAttempt)
  , Routed (Routed)
  , SessionId
  , SlmName (SlmName)
  )
import           Control.Category ((>>>))
import           Control.Concurrent (modifyMVar_, readMVar)
import           Control.Concurrent.STM
  ( TChan
  , atomically
  , tryReadTChan
  , writeTChan
  )
import           Control.Exception (try)
import           Control.Monad (foldM)
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
  , alter
  , assocs
  , elems
  , fromList
  , insert
  , keys
  , lookup
  , unionWith
  )
import           Data.Monoid (Last (Last))
import           Data.Pool (withResource)
import qualified Data.Set as Set
  ( delete
  , filter
  , fromList
  , insert
  , member
  , null
  , toList
  )
import           Database.PostgreSQL.Simple (Connection, SqlError, execute)
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           Database.PostgreSQL.Simple.Types (PGArray (PGArray))
import           DSL.Builder
  ( WorldBuilderResult (WorldBuilderResult, resultChanges, resultCounters, resultGameState)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  , worldBuilderErrorText
  , worldChangeText
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
import           Grammar.Gbnf
  ( UnparsedSentence (UnparsedSentence)
  , generateGbnf
  )
import           Grammar.Lexer (lexify, tokens)
import           Grammar.Parser.Composites.Model (Sentence)
import           Grammar.Parser.Composites.Nouns (PlayerName (PlayerName))
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
  , SceneLabel (SceneLabel)
  , agentKind
  , agentLocationMap
  , agentMap
  , agentShortName
  , declaredSceneGIDs
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
import           Model.GID (GID (unGID))
import           Model.Mid (Mid (Mid))
import           Model.RichText
  ( RichText
  , TextColor (White)
  , colored
  , plain
  , toPlainText
  )
import           Model.WireProtocol
  ( MessageFrom (ChatMessage, GameNarration, Pong, RepairRequest, SystemMessage)
  )
import           Server.App
  ( AppCtx (acBuilderCounters, acDSLChan, acDbPool, acGameLog, acInbound, acJoinChan, acKnownPlayers, acOutbound, acPendingRepairs, acSessions)
  , PendingRepair (PendingRepair)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingJoin, AwaitingSocket, InGame)
  , sessionGid
  )
import           Server.Log
  ( LogEntry (DSLBuildFailed, DSLBuildSucceeded)
  , writeLog
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
    let runSubmission prev (Routed sid dsl) =
          case runWorldBuilder (interpretDSL dsl)
                 (initialBuilderState (resultGameState prev) (resultCounters prev)) of
            Left err -> do
              liftIO $ writeLog (acGameLog appCtx) (DSLBuildFailed err)
              liftIO . atomically $ writeTChan (acOutbound appCtx) (Routed sid (GameNarration (mempty { _actionConsequence = [plain (worldBuilderErrorText err)] })))
              pure prev
            Right next -> do
              liftIO $ writeLog (acGameLog appCtx) (DSLBuildSucceeded (resultChanges next))
              liftIO . atomically $ writeTChan (acOutbound appCtx) (Routed sid (GameNarration (mempty { _actionConsequence = fmap (plain . worldChangeText) (resultChanges next) })))
              pure next
    result <- foldM runSubmission (WorldBuilderResult gs counters []) submissions
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
  pending <- liftIO $ readMVar (acPendingRepairs appCtx)

  -- GENERATE: compose one big GameComputation
  let names = [PlayerName (view unPlayerNameVAL name) | name <- keys known]
        <> [PlayerName (view unPlayerNameVAL name) | NewPlayerJoined _ name _ <- joinResults]
      (pings, replies, updates, failureRows, successRows, commandComp) = resolveCommands sessions pending names msgs
      (joinResults, joinComp) = processJoinsPure known joins
      leavesComp = processLeavesPure sessions known
      tickComp = composeTick leavesComp joinComp commandComp (joinGIDs joinResults)

      -- EXECUTE: run once
      (result, gs') = runPureComputation tickComp gs
      rowContext sid = do
        gid <- lookup sid sessions >>= sessionGid
        sceneGid <- lookup gid (view agentLocationMap gs)
        case [label | (label, declared) <- assocs (view (world . declaredSceneGIDs) gs), declared == sceneGid] of
          [label] -> Just (label, Mid (unGID gid))
          _       -> Nothing

  -- IO: protocol replies (delivered regardless of tick result)
  liftIO . forM_ pings $ \sid ->
    atomically $ writeTChan (acOutbound appCtx) (Routed sid Pong)
  liftIO . forM_ replies $ atomically . writeTChan (acOutbound appCtx)
  liftIO . modifyMVar_ (acPendingRepairs appCtx) $ \pendingMap ->
    pure (foldl' (\acc (sid, update) -> alter (const update) sid acc) pendingMap updates)
  liftIO . forM_ failureRows $ \(sid, unparsed, failure, attempts, slm) ->
    case rowContext sid of
      Nothing -> hPutStrLn stderr ("Repair failure row skipped, no actor scene for " <> show sid)
      Just (label, actor) -> do
        written :: Either SqlError () <- try . withResource (acDbPool appCtx) $ \conn ->
          insertRepairFailure conn label actor unparsed failure attempts slm
        case written of
          Left err -> hPutStrLn stderr ("Repair failure row not written: " <> show err)
          Right () -> pure ()
  liftIO . forM_ successRows $ \(sid, unparsed, rewrite, slm) ->
    case rowContext sid of
      Nothing -> hPutStrLn stderr ("Repair success row skipped, no actor scene for " <> show sid)
      Just (label, actor) -> do
        written :: Either SqlError () <- try . withResource (acDbPool appCtx) $ \conn ->
          insertRepairSuccess conn label actor unparsed rewrite slm
        case written of
          Left err -> hPutStrLn stderr ("Repair success row not written: " <> show err)
          Right () -> pure ()

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
  forM_ joinedGids $ \gid ->
    case lexify tokens "look" >>= parseTokens of
      Left err       -> throwError err
      Right sentence -> runEvalFor gid sentence
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

runEvalFor :: GID Agent -> Sentence -> GameComputation Identity ()
runEvalFor gid sentence = do
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
                -> Map SessionId PendingRepair
                -> [PlayerName]
                -> [Routed MessageTo]
                -> ( [SessionId]
                   , [Routed MessageFrom]
                   , [(SessionId, Maybe PendingRepair)]
                   , [(SessionId, UnparsedSentence, ParseFailure, [RepairAttempt], SlmName)]
                   , [(SessionId, UnparsedSentence, Text, SlmName)]
                   , GameComputation Identity ()
                   )
resolveCommands sessions pending names msgs =
  (pings, replies, updates, exhausted, successRows, mapM_ commandComputation sentences)
  where
    pings     = [sid | Routed sid Ping <- msgs]
    cmds      = [(sid, UnparsedSentence cmdText, lexify tokens cmdText >>= parseTokens) | Routed sid (GameCommand cmdText) <- msgs]
    repaired  = [(sid, unparsed, rewrite, slm, lexify tokens rewrite >>= parseTokens) | Routed sid (RepairedCommand unparsed rewrite slm) <- msgs]
    unparsedCmds = [(sid, unparsed, ParseFailure err) | (sid, unparsed, Left err) <- cmds]
    repairedSentences = [(sid, unparsed, rewrite, slm, sentence) | (sid, unparsed, rewrite, slm, Right sentence) <- repaired]
    repairErrors = [(sid, unparsed, rewrite, slm, err) | (sid, unparsed, rewrite, slm, Left err) <- repaired]
    unpending = [(sid, err) | (sid, _, _, _, err) <- repairErrors, Nothing <- [lookup sid pending]]
    judged =
      [ (sid, unparsed, origErr, attempts, slm, slm == SlmName "slm-absent" || length attempts >= 3)
      | (sid, unparsed, rewrite, slm, err) <- repairErrors
      , Just (PendingRepair _ origErr prior) <- [lookup sid pending]
      , let attempts = prior <> [RepairAttempt rewrite (ParseFailure err)]
      ]
    exhausted = [(sid, unparsed, origErr, attempts, slm) | (sid, unparsed, origErr, attempts, slm, True) <- judged]
    retries   = [(sid, unparsed, origErr, attempts) | (sid, unparsed, origErr, attempts, _, False) <- judged]
    replies =
      [Routed sid (RepairRequest unparsed failure (generateGbnf unparsed names) []) | (sid, unparsed, failure) <- unparsedCmds]
      <> [Routed sid (SystemMessage err) | (sid, err) <- unpending]
      <> [Routed sid (SystemMessage origText) | (sid, _, ParseFailure origText, _, _) <- exhausted]
      <> [Routed sid (RepairRequest unparsed origErr (generateGbnf unparsed names) attempts) | (sid, unparsed, origErr, attempts) <- retries]
    updates =
      [(sid, Just (PendingRepair unparsed failure [])) | (sid, unparsed, failure) <- unparsedCmds]
      <> [(sid, Nothing) | (sid, _, _, _, _) <- repairedSentences]
      <> [(sid, Nothing) | (sid, _) <- unpending]
      <> [(sid, Nothing) | (sid, _, _, _, _) <- exhausted]
      <> [(sid, Just (PendingRepair unparsed origErr attempts)) | (sid, unparsed, origErr, attempts) <- retries]
    successRows = [(sid, unparsed, rewrite, slm) | (sid, unparsed, rewrite, slm, _) <- repairedSentences]
    sentences =
      [(sid, sentence) | (sid, _, Right sentence) <- cmds]
      <> [(sid, sentence) | (sid, _, _, _, sentence) <- repairedSentences]
    commandComputation (sid, sentence) =
      case lookup sid sessions >>= sessionGid of
        Nothing  -> throwError ("Programmer Error: no InGame session for " <> pack (show sid))
        Just gid -> runEvalFor gid sentence

insertRepairFailure :: Connection
                    -> SceneLabel
                    -> Mid AuthenticatedUser
                    -> UnparsedSentence
                    -> ParseFailure
                    -> [RepairAttempt]
                    -> SlmName
                    -> IO ()
insertRepairFailure conn (SceneLabel scene) actor (UnparsedSentence unparsed) (ParseFailure parseError) attempts slm =
  void $ execute conn
    [sql|
      INSERT INTO repair_failures (scene, actor, unparsed_sentence, parse_error, attempts, attempt_errors, slm_id)
        VALUES (?, ?, ?, ?, ?, ?, (SELECT slm_id FROM slm WHERE name = ?))
    |]
    ( scene
    , actor
    , unparsed
    , parseError
    , PGArray [rewrite | RepairAttempt rewrite _ <- attempts]
    , PGArray [attemptError | RepairAttempt _ (ParseFailure attemptError) <- attempts]
    , slm
    )

insertRepairSuccess :: Connection
                    -> SceneLabel
                    -> Mid AuthenticatedUser
                    -> UnparsedSentence
                    -> Text
                    -> SlmName
                    -> IO ()
insertRepairSuccess conn (SceneLabel scene) actor (UnparsedSentence unparsed) rewrite slm =
  void $ execute conn
    [sql|
      INSERT INTO repair_successes (scene, actor, unparsed_sentence, rewrite, slm_id)
        VALUES (?, ?, ?, ?, (SELECT slm_id FROM slm WHERE name = ?))
    |]
    (scene, actor, unparsed, rewrite, slm)

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
