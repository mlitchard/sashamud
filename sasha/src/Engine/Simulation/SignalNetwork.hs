{-# LANGUAGE QuasiQuotes #-}
{-# OPTIONS_GHC -fsimpl-tick-factor=200 #-}

module Engine.Simulation.SignalNetwork
  ( PlayerLookup (PlayerWordsFound, PlayerLookupFailed)
  , RhineM
  , formatState
  , gameLoop
  , insertRepairFailure
  , insertRepairSuccess
  , prettyShowSentence
  , resolveCommands
  , runPureComputation
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
import           Control.Monad.Error.Class (catchError)
import           Control.Monad.Except (runExceptT, throwError)
import           Control.Monad.Schedule.Class (MonadSchedule (schedule))
import           Control.Monad.State (get, put, runStateT)
import           Control.Monad.Trans.Accum (AccumT, add, look, runAccumT)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Reader (ReaderT (runReaderT), ask)
import           Data.Aeson (ToJSON)
import           Data.Aeson.Encode.Pretty (encodePretty)
import           Data.ByteString.Lazy (toStrict)
import           Data.Functor.Identity (Identity, runIdentity)
import           Data.IORef (readIORef, writeIORef)
import           Data.List (replicate)
import           Data.Map.Strict
  ( Map
  , adjust
  , alter
  , assocs
  , elems
  , fromList
  , insert
  , lookup
  , unionWith
  )
import           Data.Monoid (Last (Last))
import           Data.Ord (max)
import           Data.Pool (withResource)
import           Data.Set (Set)
import qualified Data.Set (toList)
import qualified Data.Set as Set
  ( delete
  , filter
  , fromList
  , insert
  , member
  , null
  , toList
  )
import           Data.Text (lines, toLower)
import           Data.Text.Encoding (decodeUtf8')
import           Database.PostgreSQL.Simple
  ( Connection
  , Only (Only)
  , SqlError
  , execute
  , query
  )
import           Database.PostgreSQL.Simple.SqlQQ (sql)
import           Database.PostgreSQL.Simple.Types (PGArray (PGArray))
import           DSL.Builder
  ( WorldBuilderResult (resultChanges, resultCounters, resultGameState)
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
import           Grammar.Lexer (Lexeme (AGENTNAME, UNKNOWN), lexify, tokens)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulusPlayer (DirectionalStimulusPlayer)
  )
import           Grammar.Parser.Composites.Model (Sentence)
import           Grammar.Parser.Composites.Nouns (PlayerName (PlayerName))
import           Grammar.Parser.GCase
  ( NounKey (DirectionalStimulusPlayerKey)
  , VerbKey (AcquisitionKey, DivestmentKey, ImperativeKey, ImplicitStimulusKey)
  )
import           Grammar.Sentence (parseTokens)
import           Lens.Micro.Platform
  ( at
  , non
  , over
  , set
  , use
  , view
  , (%~)
  , (.=)
  , (.~)
  , (?~)
  )
import           Model.Core
  ( ActionManagement (AVSupportManagementKey, AVTargetManagementKey, DSAManagementKey, DSATargetManagementKey, DVManagementKey, DVSurfaceManagementKey, ISAManagementKey, ISATargetManagementKey)
  , Agent
  , AgentKey (AgentKey)
  , AgentKind (Denizen)
  , Entity (AgentEntity)
  , EntityKey (EntityAgent)
  , Evaluator (Evaluator)
  , GameComputation (runGameComputation)
  , GameError (ActorError, AgentLocationMissing, AgentMissing, EvaluatorMissing, NewUserStartSceneMissing, NewUserTemplateMissing, ParseFailed, SceneMissing, SessionMissing, SharedWitnessMissing)
  , GameState
  , GameStateT (runGameStateT)
  , Narration (Narration, _actionConsequence, _actionEpilogue, _playerAction, _presenceListing)
  , NarrationMap (NarrationMap)
  , SceneLabel (SceneLabel)
  , actionManagementFunctions
  , agentActionManagement
  , agentKind
  , agentLocationMap
  , agentMap
  , agentSemanticMap
  , agentShortName
  , agentWitnessMap
  , declaredSceneGIDs
  , evaluation
  , gameErrorText
  , getAgentMap
  , getGIDToDataMap
  , narrationMap
  , newUserMkAgent
  , newUserStartScene
  , objectMap
  , possibilityGraph
  , runEvaluator
  , sceneAgents
  , sceneMap
  , sceneObjects
  , sharedActionManagement
  , sharedWitnessManagement
  , unNarrationMap
  , world
  )
import           Model.GID (GID (GID, unGID))
import           Model.Mid (Mid (Mid))
import           Model.RichText
  ( RichText
  , TextColor (White)
  , colored
  , plain
  , toPlainText
  )
import           Model.WireProtocol
  ( AnalysisViewport (Parser, State)
  , MessageFrom (AnalysisData, ChatMessage, GameNarration, Pong, RepairRequest, SystemMessage)
  )
import           Server.App
  ( AppCtx (acBuilderCounters, acDSLChan, acDbPool, acGameLog, acInbound, acJoinChan, acLastStateViews, acOutbound, acPendingRepairs, acSessions)
  , DslResult (DslResult, dslResultCounters, dslResultReports, dslResultState)
  , JoinResult (NewPlayerJoined, ReturningPlayerJoined)
  , PendingRepair (PendingRepair)
  , PlayerResult (PlayerResult, playerResultJoins, playerResultNarrations, playerResultRepairReplies, playerResultState)
  , SessionPhase (SessionPhase)
  , SessionState (AwaitingJoin, AwaitingSocket, InGame)
  , sessionGid
  )
import           Server.Log
  ( LogEntry (DSLBuildFailed, DSLBuildSucceeded, TickFailed)
  , writeLog
  )
import           Server.Validator (unPlayerNameVAL)
import           System.Exit (exitFailure)
import           System.Posix.Syslog (Priority (Emergency))
import           Systemd.Journal (priority, sendMessageWith)

data PlayerLookup = PlayerWordsFound (Set PlayerName)
                  | PlayerLookupFailed SqlError

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
    counters <- liftIO $ readIORef (acBuilderCounters appCtx)
    let runSubmission acc (Routed sid dsl) =
          case runWorldBuilder (interpretDSL dsl)
                 (initialBuilderState (dslResultState acc) (dslResultCounters acc)) of
            Left err   -> DslResult (dslResultState acc) (dslResultCounters acc) (dslResultReports acc <> [Routed sid (Left err)])
            Right next -> DslResult (resultGameState next) (resultCounters next) (dslResultReports acc <> [Routed sid (Right (resultChanges next))])
        f gs = Right (foldl' runSubmission (DslResult gs counters []) submissions)
    gs <- lookGameState
    case f gs of
      Left err -> liftIO $ do
        sendMessageWith (worldBuilderErrorText err) (priority Emergency)
        exitFailure
      Right result -> do
        addGameState (dslResultState result)
        liftIO $ do
          writeIORef (acBuilderCounters appCtx) (dslResultCounters result)
          forM_ (dslResultReports result) $ \case
            Routed sid (Left err) -> do
              writeLog (acGameLog appCtx) (DSLBuildFailed err)
              atomically $ writeTChan (acOutbound appCtx) (Routed sid (GameNarration (mempty { _actionConsequence = [plain (worldBuilderErrorText err)] })))
            Routed sid (Right changes) -> do
              writeLog (acGameLog appCtx) (DSLBuildSucceeded changes)
              atomically $ writeTChan (acOutbound appCtx) (Routed sid (GameNarration (mempty { _actionConsequence = fmap (plain . worldChangeText) changes })))

playerTickBlock :: ClSF RhineM (IOClock RhineM PlayerTick) () ()
playerTickBlock = constMCl $ do
  appCtx <- askAppCtx

  -- IO: gather inputs
  sessions <- liftIO $ readMVar (acSessions appCtx)
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  msgs <- liftIO $ drainChan (acInbound appCtx)
  let joining = fromList [(sid, gid) | PlayerJoined sid _ gid <- joins]
  pending <- liftIO $ readMVar (acPendingRepairs appCtx)
  let sentenceTexts = [cmdText | Routed _ (GameCommand cmdText) <- msgs]
                   <> [rewrite | Routed _ (RepairedCommand _ rewrite _) <- msgs]
      unknownWords  = [w | txt <- sentenceTexts, Right lexemes <- [lexify tokens (toLower txt)], UNKNOWN w <- lexemes]
  playerLookup <- liftIO $ case unknownWords of
    [] -> pure (PlayerWordsFound mempty)
    _  -> do
      found :: Either SqlError [(GID Agent, PlayerName)] <- try . withResource (acDbPool appCtx) $ \conn ->
        selectPlayerWords conn unknownWords
      case found of
        Left err    -> do
          hPutStrLn stderr ("Player lookup failed: " <> show err)
          pure (PlayerLookupFailed err)
        Right rows  -> pure (PlayerWordsFound (Set.fromList [playerName | (_, playerName) <- rows]))

  -- GENERATE: compose one big GameComputation
  let (pings, replies, updates, failureRows, successRows, commandComp) = resolveCommands sessions joining pending playerLookup msgs
      leavesComp = processLeavesPure sessions
      f gs =
        let (joinResults, joinComp) = processJoinsPure (view (world . agentMap . getAgentMap) gs) joins
            tickComp = composeTick leavesComp joinComp commandComp (joinGIDs joinResults)
            (result, gs') = runPureComputation tickComp gs
        in case result of
             Left err -> Left err
             Right (narrations, repairReplies) -> Right (PlayerResult narrations repairReplies joinResults gs')

  -- IO: protocol replies (delivered regardless of tick result)
  liftIO . forM_ pings $ \sid ->
    atomically $ writeTChan (acOutbound appCtx) (Routed sid Pong)
  liftIO . forM_ replies $ atomically . writeTChan (acOutbound appCtx)
  liftIO . modifyMVar_ (acPendingRepairs appCtx) $ \pendingMap ->
    pure (foldl' (\acc (sid, update) -> alter (const update) sid acc) pendingMap updates)

  gs <- lookGameState
  case f gs of
    Right result -> do
      addGameState (playerResultState result)
      let gs' = playerResultState result
          rowContext sid = do
            gid <- lookup sid sessions >>= sessionGid
            sceneGid <- lookup gid (view agentLocationMap gs')
            case [label | (label, declared) <- assocs (view (world . declaredSceneGIDs) gs'), declared == sceneGid] of
              [label] -> Just (label, Mid (unGID gid))
              _       -> Nothing
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
      -- IO: execute join effects (session promotion, welcome messages)
      liftIO $ forM_ (playerResultJoins result) (executeJoinIO appCtx)
      -- IO: deliver narrations to clients
      liftIO $ deliverNarrationIO appCtx (playerResultNarrations result)
      liftIO . forM_ (playerResultRepairReplies result) $ atomically . writeTChan (acOutbound appCtx)
      liftIO $ do
        liveSessions <- readMVar (acSessions appCtx)
        let views = fromList [(sid, formatState gid gs') | (sid, phase) <- assocs liveSessions, Just gid <- [sessionGid phase]]
        modifyMVar_ (acLastStateViews appCtx) $ \lastViews -> do
          forM_ (assocs views) $ \(sid, stateView) ->
            when (lookup sid lastViews /= Just stateView) . atomically $
              writeTChan (acOutbound appCtx) (Routed sid (AnalysisData [(State, stateView)]))
          pure views
    Left err -> liftIO $ do
      case err of
        ActorError gid inner -> do
          atomically . forM_ [sid | (sid, phase) <- assocs sessions, sessionGid phase == Just gid] $ \sid -> do
            writeTChan (acOutbound appCtx) (Routed sid (SystemMessage (gameErrorText inner)))
            writeTChan (acOutbound appCtx) (Routed sid (GameNarration (mempty { _actionConsequence = [plain (gameErrorText inner)] })))
          writeLog (acGameLog appCtx) (TickFailed (ActorError gid inner))
        _ -> writeLog (acGameLog appCtx) (TickFailed err)

composeTick :: GameComputation Identity ()
            -> GameComputation Identity ()
            -> GameComputation Identity [Routed MessageFrom]
            -> [GID Agent]
            -> GameComputation Identity (Map AgentKey Narration, [Routed MessageFrom])
composeTick leavesComp joinComp commandComp joinedGids = do
  leavesComp
  joinComp
  repairReplies <- commandComp
  forM_ joinedGids $ \gid ->
    case lexify tokens "look" >>= parseTokens of
      Left err       -> throwError (ParseFailed err)
      Right sentence -> runEvalFor gid sentence
  narrations <- extractNarration
  pure (narrations, repairReplies)

processLeavesPure :: Map SessionId SessionPhase
                  -> GameComputation Identity ()
processLeavesPure sessions = do
  gs <- get
  let activeGids = Set.fromList [gid | phase <- elems sessions, Just gid <- [sessionGid phase]]
      knownGids = Set.fromList [gid | (gid, _) <- assocs aMap]
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
            scene' = foldr (\(gid, key) sc -> over agentSemanticMap (adjust (Set.delete gid) key) sc)
                       (set sceneAgents remaining scene)
                       [ (gid, DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME (toPlainText (view agentShortName a)))))
                       | gid <- Set.toList departed
                       , Just a <- [lookup gid aMap]
                       ]
            departNarr = mconcat
              [ consequenceNarration (view agentShortName a <> plain " has departed.")
              | gid <- Set.toList departed
              , Just a <- [lookup gid aMap]
              ]
            departedGs = foldl' (\acc gid -> acc & agentWitnessMap . at (AgentKey gid) .~ Nothing) currentGs (toList departed)
        in departedGs
             & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
             & announceToDenizens aMap (Set.toList remaining) departNarr
  put (foldl' applyDeparture gs sceneDepartures)

processJoinsPure :: Map (GID Agent) Agent
                 -> [PlayerJoined]
                 -> ([JoinResult], GameComputation Identity ())
processJoinsPure aMap joins = (joinResults, mapM_ joinComputation joinResults)
  where
    joinResults = fmap classify joins
    classify (PlayerJoined sid name accountGid) =
      case lookup accountGid aMap of
        Just _  -> ReturningPlayerJoined sid accountGid
        Nothing -> NewPlayerJoined sid name accountGid
    joinComputation (ReturningPlayerJoined _sid gid) = (do
      gs <- get
      case lookup gid (view (world . agentMap . getAgentMap) gs) of
        Nothing -> throwError (AgentMissing gid)
        Just agent ->
          case lookup gid (view agentLocationMap gs) of
            Nothing -> throwError (AgentLocationMissing gid)
            Just sceneGid ->
              case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
                Nothing -> throwError (SceneMissing sceneGid)
                Just scene ->
                  case lookup AgentEntity (view (world . sharedWitnessManagement) gs) of
                    Nothing -> throwError SharedWitnessMissing
                    Just witnessGid -> do
                      let currentAMap = view (world . agentMap . getAgentMap) gs
                          key = DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME (toPlainText (view agentShortName agent))))
                          scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
                            & agentSemanticMap . at key . non mempty %~ Set.insert gid
                          announceNarration = consequenceNarration (colored White (toPlainText (view agentShortName agent) <> " has arrived."))
                          others = [g | g <- Set.toList (view sceneAgents scene'), g /= gid]
                          gs' = gs
                            & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
                            & agentWitnessMap . at (AgentKey gid) ?~ fromList [(EntityAgent g, witnessGid) | g <- others]
                            & over agentWitnessMap (flip (unionWith (<>)) (fromList [(AgentKey g, fromList [(EntityAgent gid, witnessGid)]) | g <- others]))
                            & announceToDenizens currentAMap others announceNarration
                      put gs') `catchError` \err -> throwError (ActorError gid err)
    joinComputation (NewPlayerJoined _sid name gid) = (do
      gs <- get
      case view (possibilityGraph . newUserStartScene) gs of
        Nothing -> throwError NewUserStartSceneMissing
        Just sceneGid ->
          case view (possibilityGraph . newUserMkAgent) gs of
            Nothing -> throwError NewUserTemplateMissing
            Just mkAgent ->
              case lookup AgentEntity (view (world . sharedWitnessManagement) gs) of
                Nothing -> throwError SharedWitnessMissing
                Just witnessGid ->
                  case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
                    Nothing -> throwError (SceneMissing sceneGid)
                    Just scene -> do
                      let agent = mkAgent (view unPlayerNameVAL name)
                          currentAMap = view (world . agentMap . getAgentMap) gs
                          key = DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME (toPlainText (view agentShortName agent))))
                          scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
                            & agentSemanticMap . at key . non mempty %~ Set.insert gid
                          announceNarration = consequenceNarration (colored White (view unPlayerNameVAL name <> " has arrived."))
                          others = [g | g <- Set.toList (view sceneAgents scene'), g /= gid]
                          gs' = gs
                            & world . agentMap . getAgentMap . at gid ?~ agent
                            & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
                            & agentLocationMap . at gid ?~ sceneGid
                            & agentWitnessMap . at (AgentKey gid) ?~ fromList [(EntityAgent g, witnessGid) | g <- others]
                            & over agentWitnessMap (flip (unionWith (<>)) (fromList [(AgentKey g, fromList [(EntityAgent gid, witnessGid)]) | g <- others]))
                            & announceToDenizens currentAMap others announceNarration
                            & evaluation . at gid ?~ Evaluator eval
                      put gs') `catchError` \err -> throwError (ActorError gid err)

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
  in over (narrationMap . unNarrationMap) (flip (unionWith (<>)) (fromList [(AgentKey g, narr) | g <- recipients]))

extractNarration :: GameComputation Identity (Map AgentKey Narration)
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
  view runEvaluator evaluator gid sentence `catchError` \err -> throwError (ActorError gid err)

lookupEvaluatorOrThrow :: GID Agent -> GameComputation Identity Evaluator
lookupEvaluatorOrThrow gid = do
  evals <- use evaluation
  case lookup gid evals of
    Nothing        -> throwError (EvaluatorMissing gid)
    Just evaluator -> pure evaluator

runPureComputation :: GameComputation Identity a
                   -> GameState
                   -> (Either GameError a, GameState)
runPureComputation comp gs =
  runIdentity (runStateT (runGameStateT (runExceptT (runGameComputation comp))) gs)

resolveCommands :: Map SessionId SessionPhase
                -> Map SessionId (GID Agent)
                -> Map SessionId PendingRepair
                -> PlayerLookup
                -> [Routed MessageTo]
                -> ( [SessionId]
                   , [Routed MessageFrom]
                   , [(SessionId, Maybe PendingRepair)]
                   , [(SessionId, UnparsedSentence, ParseFailure, [RepairAttempt], SlmName)]
                   , [(SessionId, UnparsedSentence, Text, SlmName)]
                   , GameComputation Identity [Routed MessageFrom]
                   )
resolveCommands sessions joining pending playerLookup msgs =
  (pings, replies, updates, exhausted, successRows, commandsAndRepairs)
  where
    found = case playerLookup of
      PlayerWordsFound playerNames -> playerNames
      PlayerLookupFailed _         -> mempty
    actorGid sid = case lookup sid sessions >>= sessionGid of
      Just gid -> Just gid
      Nothing  -> lookup sid joining
    names = Set.toList found
    promote = \case
      UNKNOWN w | Set.member (PlayerName w) found -> AGENTNAME w
      lexeme                                      -> lexeme
    pings     = [sid | Routed sid Ping <- msgs]
    cmds =
      [ (sid, UnparsedSentence cmdText, commandLines cmdText lexed parsed, parsed)
      | Routed sid (GameCommand typed) <- msgs
      , let cmdText = toLower typed
      , let lexed = fmap (fmap promote) (lexify tokens cmdText)
      , let parsed = lexed >>= parseTokens
      ]
    repaired =
      [ (sid, unparsed, rewrite, slm, attemptLines unparsed (lookup sid pending) rewrite slm lexed parsed, parsed)
      | Routed sid (RepairedCommand unparsed rewriteText slm) <- msgs
      , let rewrite = toLower rewriteText
      , let lexed = fmap (fmap promote) (lexify tokens rewrite)
      , let parsed = lexed >>= parseTokens
      ]
    unparsedCmds = [(sid, unparsed, ParseFailure err) | (sid, unparsed, _, Left err) <- cmds]
    repairedSentences = [(sid, unparsed, rewrite, slm, attemptView, sentence) | (sid, unparsed, rewrite, slm, attemptView, Right sentence) <- repaired]
    repairErrors = [(sid, unparsed, rewrite, slm, attemptView, err) | (sid, unparsed, rewrite, slm, attemptView, Left err) <- repaired]
    unpending = [(sid, attemptView, err) | (sid, _, _, _, attemptView, err) <- repairErrors, Nothing <- [lookup sid pending]]
    judged =
      [ (sid, unparsed, origErr, attempts, slm, attemptView <> [plain "=== Outcome ==="] <> outcomeLines, done)
      | (sid, unparsed, rewrite, slm, attemptView, err) <- repairErrors
      , Just (PendingRepair _ origErr prior) <- [lookup sid pending]
      , let attempts = prior <> [RepairAttempt rewrite (ParseFailure err)]
      , let (outcomeLines, done) = repairOutcome slm attempts
      ]
    exhausted = [(sid, unparsed, origErr, attempts, slm) | (sid, unparsed, origErr, attempts, slm, _, True) <- judged]
    retries   = [(sid, unparsed, origErr, attempts) | (sid, unparsed, origErr, attempts, _, _, False) <- judged]
    replies =
      [Routed sid (AnalysisData [(Parser, commandView)]) | (sid, _, commandView, _) <- cmds]
      <> [Routed sid (AnalysisData [(Parser, attemptView <> [plain "=== Outcome ===", plain "  parsed, the sentence runs"] <> parseLines (Right sentence))]) | (sid, _, _, _, attemptView, sentence) <- repairedSentences]
      <> [Routed sid (AnalysisData [(Parser, attemptView <> [plain "=== Outcome ===", plain "  no repair pending"])]) | (sid, attemptView, _) <- unpending]
      <> [Routed sid (AnalysisData [(Parser, judgedView)]) | (sid, _, _, _, _, judgedView, _) <- judged]
      <> [Routed sid (SystemMessage err) | (sid, _, err) <- unpending]
      <> [Routed sid (SystemMessage origText) | (sid, _, ParseFailure origText, _, _) <- exhausted]
    updates =
      [(sid, Just (PendingRepair unparsed failure [])) | (sid, unparsed, failure) <- unparsedCmds]
      <> [(sid, Nothing) | (sid, _, _, _, _, _) <- repairedSentences]
      <> [(sid, Nothing) | (sid, _, _) <- unpending]
      <> [(sid, Nothing) | (sid, _, _, _, _) <- exhausted]
      <> [(sid, Just (PendingRepair unparsed origErr attempts)) | (sid, unparsed, origErr, attempts) <- retries]
    successRows = [(sid, unparsed, rewrite, slm) | (sid, unparsed, rewrite, slm, _, _) <- repairedSentences]
    sentences =
      [(sid, sentence) | (sid, _, _, Right sentence) <- cmds]
      <> [(sid, sentence) | (sid, _, _, _, _, sentence) <- repairedSentences]
    commandComputation (sid, sentence) =
      case actorGid sid of
        Nothing  -> throwError (SessionMissing sid)
        Just gid -> runEvalFor gid sentence
    commandsAndRepairs = do
      firstRequests <- mapM firstRepairRequest unparsedCmds
      retryRequests <- mapM retryRepairRequest retries
      mapM_ commandComputation sentences
      pure (firstRequests <> retryRequests)
    firstRepairRequest (sid, unparsed, failure) = do
      verbs <- actorVerbs sid
      pure (Routed sid (RepairRequest unparsed failure (generateGbnf unparsed names verbs) []))
    retryRepairRequest (sid, unparsed, origErr, attempts) = do
      verbs <- actorVerbs sid
      pure (Routed sid (RepairRequest unparsed origErr (generateGbnf unparsed names verbs) attempts))
    actorVerbs sid = do
      aMap <- use (world . agentMap . getAgentMap)
      sharedTables <- use (world . sharedActionManagement)
      let actor = do
            gid <- actorGid sid
            lookup gid aMap
      case actor of
        Nothing    -> throwError (SessionMissing sid)
        Just agent -> pure (verbsFor sharedTables agent)
    verbsFor sharedTables agent =
      fill [key | key@(ImplicitStimulusKey _) <- own] [key | key@(ImplicitStimulusKey _) <- shared]
      <> fill [key | key@(ImperativeKey _) <- own] [key | key@(ImperativeKey _) <- shared]
      <> fill [key | key@(AcquisitionKey _) <- own] [key | key@(AcquisitionKey _) <- shared]
      <> fill [key | key@(DivestmentKey _) <- own] [key | key@(DivestmentKey _) <- shared]
      where
        own = [key | action <- Set.toList (view (agentActionManagement . actionManagementFunctions) agent), Just key <- [verbKeyOf action]]
        shared =
          [ key
          | entityTables <- elems sharedTables
          , Just functions <- [lookup AgentEntity entityTables]
          , action <- Set.toList (view actionManagementFunctions functions)
          , Just key <- [verbKeyOf action]
          ]
    fill [] fallback = fallback
    fill keys _      = keys
    verbKeyOf = \case
      ISAManagementKey verb _      -> Just (ImplicitStimulusKey verb)
      DSAManagementKey verb _      -> Just (ImperativeKey verb)
      AVTargetManagementKey verb _ -> Just (AcquisitionKey verb)
      DVManagementKey verb _       -> Just (DivestmentKey verb)
      ISATargetManagementKey _ _   -> Nothing
      DSATargetManagementKey _ _   -> Nothing
      AVSupportManagementKey _ _   -> Nothing
      DVSurfaceManagementKey _ _   -> Nothing
    lexemeLines = \case
      Left err      -> fmap plain (lines err)
      Right lexemes -> [plain ("  " <> pack (show lexemes))]
    parseLines = \case
      Left err       -> fmap plain (lines err)
      Right sentence -> fmap plain (lines (prettyShowSentence sentence))
    commandLines cmdText lexed parsed =
      [plain "=== Input ===", plain ("  " <> cmdText), plain "=== Lexemes ==="]
      <> lexemeLines lexed
      <> [plain "=== Sentence ==="]
      <> parseLines parsed
      <> case parsed of
           Left _  -> [plain "=== Repair ===", plain "  repair requested"]
           Right _ -> []
    attemptLines (UnparsedSentence original) pendingRepair rewrite (SlmName slmName) lexed parsed =
      [plain "=== Input ===", plain ("  " <> original)]
      <> inputFailure
      <> [plain "=== Repair attempts ==="]
      <> concatMap priorAttemptLines prior
      <> [plain ("  Rewrite: " <> rewrite <> " (SLM " <> slmName <> ")")]
      <> lexemeLines lexed
      <> case parsed of
           Left err -> parseLines (Left err)
           Right _  -> []
      where
        (inputFailure, prior) = case pendingRepair of
          Nothing                                                 -> ([], [])
          Just (PendingRepair _ (ParseFailure origText) attempts) -> (parseLines (Left origText), attempts)
    priorAttemptLines (RepairAttempt rewrite (ParseFailure err)) =
      [plain ("  Rewrite: " <> rewrite)]
      <> lexemeLines (lexify tokens rewrite)
      <> parseLines (Left err)
    repairOutcome slm attempts
      | slm == SlmName "slm-absent" = ([plain "  slm-absent"], True)
      | length attempts >= 3        = ([plain ("  repair ended after " <> pack (show (length attempts)) <> " attempts")], True)
      | otherwise                   = ([plain ("  failed, asking the SLM again (attempt " <> pack (show (length attempts)) <> " of 3)")], False)

prettyShowSentence :: Sentence -> Text
prettyShowSentence sentence = pack $ go 0 (show sentence)
  where
    go :: Int -> String -> String
    go _ [] = []
    go indent ('(':rest) =
      '\n' : (replicate (indent * 2) ' ' <> ('(' : go (indent + 1) rest))
    go indent (')':rest) =
      ')' : go (max 0 (indent - 1)) rest
    go indent (c:rest) =
      c : go indent rest

formatState :: GID Agent -> GameState -> [RichText]
formatState gid gs =
  case lookup gid (view agentLocationMap gs) of
    Nothing -> [plain ("Location missing for GID " <> pack (show gid))]
    Just sceneGid ->
      case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
        Nothing -> [plain ("Scene missing for GID " <> pack (show sceneGid))]
        Just scene ->
          [plain "=== Agents ==="]
          <> formatSection (Data.Set.toList (view sceneAgents scene)) (view (world . agentMap . getAgentMap) gs)
          <> [plain "=== Objects ==="]
          <> formatSection (Data.Set.toList (view sceneObjects scene)) (view (world . objectMap . getGIDToDataMap) gs)
  where
    formatSection :: ToJSON a => [GID a] -> Map (GID a) a -> [RichText]
    formatSection [] _          = [plain "  (none)"]
    formatSection gids entities = concatMap (formatEntity entities) gids
    formatEntity :: ToJSON a => Map (GID a) a -> GID a -> [RichText]
    formatEntity entities entityGid =
      case lookup entityGid entities of
        Nothing -> [plain ("  GID " <> pack (show entityGid) <> " missing")]
        Just entity ->
          [plain ("  GID " <> pack (show entityGid))]
          <> case decodeUtf8' (toStrict (encodePretty entity)) of
               Left err   -> [plain ("  " <> pack (show err))]
               Right json -> fmap (plain . ("  " <>)) (lines json)

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

selectPlayerWords :: Connection -> [Text] -> IO [(GID Agent, PlayerName)]
selectPlayerWords conn candidates = do
  rows :: [(Int, Text)] <- query conn
    [sql|
      SELECT agent_id, name FROM agents
        WHERE name = ANY (?)
    |]
    (Only (PGArray candidates))
  pure [(GID agentId, PlayerName name) | (agentId, name) <- rows]

executeJoinIO :: AppCtx -> JoinResult -> IO ()
executeJoinIO ctx (NewPlayerJoined sid name _gid) = do
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
                   -> Map AgentKey Narration
                   -> IO ()
deliverNarrationIO appCtx narrations = do
  sessions <- readMVar (acSessions appCtx)
  forM_ (assocs narrations) $ \(AgentKey agentGid, narr) -> do
    let targetSids = [s | (s, phase) <- assocs sessions, sessionGid phase == Just agentGid]
    forM_ targetSids $ \targetSid ->
      atomically $ writeTChan (acOutbound appCtx) (Routed targetSid (GameNarration narr))

drainChan :: TChan a -> IO [a]
drainChan chan = do
  mMsg <- atomically (tryReadTChan chan)
  case mMsg of
    Nothing -> pure []
    Just m  -> (m :) <$> drainChan chan
