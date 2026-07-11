# Plan: Remove WorldAccum, GameState in AccumT via Last

**STATUS: APPROVED, NOT APPLIED** — WorldAccum is still live in EffectNetwork.hs. Executing this plan is the work.

## Semantic

- AccumT accumulates `Last GameState` (from Data.Monoid — wraps Maybe)
- `Last Nothing` = mempty = "no contribution" (what lift/liftIO produce)
- `Last (Just x) <> Last (Just y) = Last (Just y)` — newer wins
- `Last (Just x) <> Last Nothing = Last (Just x)` — lift doesn't wipe state
- Lawful Monoid: left identity, right identity, associativity all hold
- RhineM is a newtype that hides the Last/Maybe — signal functions use `lookGameState`/`addGameState`, never see Maybe
- Narration accumulates within a tick via StateT (GameComputation), not via the Semigroup
- Narration delivers at tick start, then flushes
- All state-modifying signal functions run sequentially on one PlayerTick (avoids parallel clock conflicts)
- One MVar read per tick phase, threaded along `>->`: deliverNarrationSF makes the tick's one pre-join acPlayerMap read and passes the snapshot to processLeavesSF; processLeavesSF makes the one acKnownPlayers read and passes it to processJoinsSF; processInputSF makes the only post-join acPlayerMap read (a new player's first command must route same-tick). No SF re-reads an MVar another SF already read.

## File 1: Model/Core.hs

### NarrationMap — Semigroup/Monoid

```haskell
instance Semigroup NarrationMap where
  NarrationMap m1 <> NarrationMap m2 = NarrationMap (Map.unionWith (<>) m1 m2)

instance Monoid NarrationMap where
  mempty = NarrationMap mempty
```

### GameState — no Semigroup/Monoid needed

GameState itself has no Semigroup or Monoid instance. `Data.Monoid.Last` provides the Monoid for AccumT. GameState is just the payload inside the `Last`.

### Narration — add JSON + TypeScript derivation

```haskell
data Narration = Narration
  { _playerAction      :: [RichText]
  , _actionConsequence :: [RichText]
  , _presenceListing   :: [RichText]
  , _actionEpilogue    :: [RichText]
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)
  deriving (Monoid, Semigroup)
    via (Generically Narration)
```

Add `FromJSON, ToJSON` to the anyclass deriving clause. Add `derivingTypeScriptDefinition ''Narration` in the TH section at the bottom of Core.hs.

### Import

Add `unionWith` to `Data.Map.Strict` import.

## File 2: Model/WireProtocol.hs

Change `GameNarration [RichText]` to `GameNarration Narration`. Add `Narration` to the import from `Model.Core`.

Add `AnalysisViewport` — the telemetry viewport keys as a sum type, replacing the raw Text key in AnalysisData (raw Text is a routing identifier here; the client silently drops unknown keys, ViewportManager.ts:65):

```haskell
data AnalysisViewport = Parser | State | Meta | Graphics | GameMap
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, FromJSONKey, NFData, ToJSON, ToJSONKey)
```

FromJSONKey/ToJSONKey are needed because AnalysisViewport is a Map key. Add `FromJSONKey, ToJSONKey` to the Data.Aeson import. Export `AnalysisViewport (..)`. Add `derivingTypeScriptDefinition ''AnalysisViewport` above MessageFrom's. In the TESTING block, add Arbitrary via GenericArbitrary (same as MessageFrom).

```haskell
data MessageFrom = SessionAck SessionId
                 | GameNarration Narration
                 | CommandResponse [RichText]
                 | ChatMessage Text
                 | SystemMessage Text
                 | Pong
                 | AnalysisData (Map AnalysisViewport [RichText])
```

No producer of AnalysisData exists yet — the web client's ANALYSIS_KEY_TO_VIEWPORT mapping (lowercase keys) gets updated to the generated union type when the telemetry producer lands.

## File 3: Server/App.hs

Add the PInt newtype and `acNextAgentId :: IORef PInt` to AppCtx. Initialize in `newAppCtx` via `newIORef firstPlayerId`. Single-thread access (one PlayerTick branch), no contention — IORef is the right primitive. Use `atomicModifyIORef'` with `succPInt` to read and increment.

```haskell
newtype PInt = PInt Int
  deriving stock (Eq, Ord, Show)

succPInt :: PInt -> PInt
succPInt (PInt n) = PInt (n + 1)

unPInt :: PInt -> Int
unPInt (PInt n) = n

firstPlayerId :: PInt
firstPlayerId = PInt 1000
```

Export `PInt` (type only — constructor NOT exported), `succPInt`, `unPInt`, `firstPlayerId`. No typeclasses: `Num` would smuggle in `(-)` and `negate`; the export list is the guarantee that the counter can only go forward. Satisfies the no-naked-types rule for the GID counter.

## File 4: Engine/Evaluators/Player/General.hs

Delete `sendMessage`, `getRecipients`. Fix eval stub:

```haskell
module Engine.Evaluators.Player.General
  ( eval
  ) where

import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (filter, keys)
import           Grammar.Parser.Composites.Model
  ( Imperative (StimulusVerbPhrase)
  , Sentence (Imperative)
  , StimulusVerbPhrase (ImplicitStimulusVerb)
  )
import           Lens.Micro.Platform (at, use, view, (.=))
import           Model.Core
  ( Agent
  , AgentKind (Denizen)
  , GameComputation
  , Narration (Narration)
  , agentKind
  , agentMap
  , getAgentMap
  , narrationMap
  , unNarrationMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)
import           SashaPrelude

eval :: GID Agent -> Sentence -> GameComputation Identity ()
eval actorGid (Imperative imperative) = evalImperative actorGid imperative

evalImperative :: GID Agent -> Imperative -> GameComputation Identity ()
evalImperative actorGid (StimulusVerbPhrase stimulusVerbPhrase) =
  evalStimulusVerbPhrase actorGid stimulusVerbPhrase

evalStimulusVerbPhrase :: GID Agent -> StimulusVerbPhrase -> GameComputation Identity ()
evalStimulusVerbPhrase _actorGid (ImplicitStimulusVerb _verb) = do
  aMap <- use (world . agentMap . getAgentMap)
  let playerGids = keys (Data.Map.Strict.filter (\agent -> view agentKind agent == Denizen) aMap)
      testNarration = Narration
        { _playerAction      = [colored White "the test worked!"]
        , _actionConsequence = []
        , _presenceListing   = []
        , _actionEpilogue    = []
        }
  forM_ playerGids $ \gid ->
    narrationMap . unNarrationMap . at gid .= Just testNarration
```

## File 5: Engine/Simulation/EffectNetwork.hs

### Delete

- WorldAccum type + Semigroup + Monoid instances + export
- Old processLeavesSF implementation (replaced with new version using RhineM interface)

### RhineM — newtype hiding Last/Maybe

```haskell
newtype RhineM a = RhineM
  { unRhineM :: AccumT (Last GameState) (ReaderT PossibilityGraph (ReaderT AppCtx IO)) a
  }
  deriving newtype (Applicative, Functor, Monad, MonadIO)

instance MonadSchedule RhineM where
  schedule = fmap (hoistS unRhineM) >>> schedule >>> hoistS RhineM
```

MonadSchedule can't be derived via newtype (Automaton's role for m is nominal — FinalizeT in Rhine's own code writes a manual instance). The manual instance unwraps to AccumT, schedules via AccumT's instance, wraps back.

### RhineM operations

```haskell
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
```

### gameLoop

```haskell
gameLoop :: AppCtx -> GameState -> PossibilityGraph -> IO ()
gameLoop ctx gs pg =
  void (runReaderT (runReaderT (runAccumT (unRhineM (flow rhinePipeline)) (Last (Just gs))) pg) ctx)
```

### rhinePipeline — all state-modifying SFs sequential on one PlayerTick

```haskell
rhinePipeline :: Rhine RhineM
  (ParallelClock
    (IOClock RhineM HeartbeatTick)
    (IOClock RhineM PlayerTick)) () ()
rhinePipeline =
    heartbeatSF @@ ioClock (waitClock :: HeartbeatTick)
    |@|
    (deliverNarrationSF >-> processLeavesSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF)
      @@ ioClock (waitClock :: PlayerTick)
```

### heartbeatSF

```haskell
heartbeatSF :: ClSF RhineM (IOClock RhineM HeartbeatTick) () ()
heartbeatSF = constMCl $ do
  appCtx <- askAppCtx
  liftIO $ do
    pMap <- readMVar (acPlayerMap appCtx)
    let msg = SystemMessage "*** heartbeat"
    atomically $
      mapM_ (\sid -> writeTChan (acOutbound appCtx) (Routed sid msg))
        (keys pMap)
```

### deliverNarrationSF — reads narration, sends to players, flushes, outputs the tick's acPlayerMap snapshot

```haskell
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
```

This is the tick's only pre-join read of acPlayerMap. The snapshot flows to processLeavesSF via `>->`.

### processLeavesSF — detects disconnected players, removes from scenes, announces departure

```haskell
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
        narrations = Map.fromList [(r, departNarr) | r <- recipientGids]
        gs' = currentGs
          & world . sceneMap . getGIDToDataMap . at sceneGid .~ Just scene'
          & over (narrationMap . unNarrationMap) (Map.unionWith (<>) narrations)
    addGameState gs'
  pure known
```

Detection is session-based: a GID in acKnownPlayers values (has joined as a player) that is absent from acPlayerMap values has no live session — departed (WebSocket disconnected, session removed). AgentKind plays no role in detection — Denizen includes NPCs, and an NPC is never in acKnownPlayers, so it is never flagged. The acPlayerMap snapshot arrives threaded from deliverNarrationSF — no re-read; a disconnect landing after that read is detected next tick. processLeavesSF makes the tick's one acKnownPlayers read and passes it to processJoinsSF. Runs before joins — if someone disconnects and reconnects in the same tick window, departure processes first, then rejoin. Departure announcements go through NarrationMap, delivered next tick by deliverNarrationSF.

### JoinError type

```haskell
data JoinFailure = ReturningAgentMissing | ReturningSceneMissing

data JoinError = JoinError SessionId JoinFailure

joinFailureText :: JoinFailure -> Text
joinFailureText ReturningAgentMissing = "returning player agent not found"
joinFailureText ReturningSceneMissing = "returning player scene not found"
```

Failure cases are a sum type — the signal chain routes on values, never on prose. joinFailureText renders at the one display boundary (executeJoinsSF → SystemMessage). JoinFailure gains constructors in future commits as join can fail in new ways.

### processJoinsSF

```haskell
processJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) (Map PlayerNameVAL (GID Agent)) [Either JoinError JoinResult]
processJoinsSF = arrMCl $ \known -> do
  appCtx <- askAppCtx
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  traverse (processOneJoin known) joins
```

Consumes the acKnownPlayers snapshot threaded from processLeavesSF — no re-read. Safe: only executeJoin writes acKnownPlayers, and it runs later in the chain.

### executeJoinsSF

```haskell
executeJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) [Either JoinError JoinResult] ()
executeJoinsSF = arrMCl $ \results -> do
  appCtx <- askAppCtx
  liftIO $ forM_ results $ \result ->
    case result of
      Left (JoinError sid failure) ->
        atomically $ writeTChan (acOutbound appCtx) (Routed sid (SystemMessage (joinFailureText failure)))
      Right joinResult ->
        executeJoin appCtx joinResult
```

### processOneJoin (returning player)

```haskell
processOneJoin :: Map PlayerNameVAL (GID Agent) -> PlayerJoined -> RhineM (Either JoinError JoinResult)
processOneJoin known (PlayerJoined sid name) =
  case lookup name known of
    Just gid -> do
      gs <- lookGameState
      case lookup gid (view (world . agentMap . getAgentMap) gs) of
        Nothing -> pure (Left (JoinError sid ReturningAgentMissing))
        Just agent -> do
          let sceneGid = view agentCurrentScene agent
          case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
            Nothing -> pure (Left (JoinError sid ReturningSceneMissing))
            Just scene -> do
              let aMap = view (world . agentMap . getAgentMap) gs
                  scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene
                  announceNarration = Narration
                    { _playerAction      = []
                    , _actionConsequence = [colored White (view agentShortName agent <> " has arrived.")]
                    , _presenceListing   = []
                    , _actionEpilogue    = []
                    }
                  recipientGids = [g | g <- Set.toList (view sceneAgents scene')
                                     , g /= gid
                                     , Just a <- [lookup g aMap]
                                     , view agentKind a == Denizen]
                  joinNarrations = Map.fromList [(g, announceNarration) | g <- recipientGids]
                  gs' = gs
                    & world . sceneMap . getGIDToDataMap . at sceneGid .~ Just scene'
                    & over (narrationMap . unNarrationMap) (Map.unionWith (<>) joinNarrations)
              addGameState gs'
              pure (Right (ReturningPlayerJoined sid name gid))
```

### processOneJoin (new player)

```haskell
    Nothing -> do
      gs <- lookGameState
      appCtx <- askAppCtx
      nextId <- liftIO $ atomicModifyIORef' (acNextAgentId appCtx) (\p -> (succPInt p, p))
      let gid = GID (unPInt nextId)
          lobbyGid = GID 0
          agent = mkDenizen name lobbyGid
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
          joinNarrations = Map.fromList [(g, announceNarration) | g <- recipientGids]
          gs' = gs
            & world . agentMap . getAgentMap . at gid .~ Just agent
            & world . sceneMap . getGIDToDataMap . at lobbyGid .~ Just lobby'
            & over (narrationMap . unNarrationMap) (Map.unionWith (<>) joinNarrations)
            & evaluation . at gid .~ Just (Evaluator eval)
      addGameState gs'
      pure (Right (NewPlayerJoined sid name gid))
```

### processInputSF — lex, parse, eval, unwrap GameComputation, add result

```haskell
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
```

### New imports needed

- `Control.Concurrent (modifyMVar_, readMVar)` — already imported, no change needed
- `Data.IORef (atomicModifyIORef')` — for GID counter
- `Data.Monoid (Last (Last))` — for AccumT accumulator
- `Control.Category ((>>>))` — for MonadSchedule instance
- `Control.Monad.State (runStateT)`
- `Control.Monad.Except (runExceptT)`
- `Control.Monad.Trans.Accum (AccumT, add, look, runAccumT)` — used inside RhineM newtype
- `Data.Functor.Identity (Identity, runIdentity)`
- `Data.Automaton.Schedule (MonadSchedule (schedule))` — for manual instance
- `Data.Automaton (hoistS)` — for MonadSchedule instance
- `Grammar.Lexer (lexify, tokens)`
- `Grammar.Sentence (parseTokens)`
- `Engine.Evaluators.Player.General (eval)` — used in processOneJoin to register evaluator via `Evaluator eval`
- `Lens.Micro.Platform` — add `at`, `over`, `set`, `(&)`, `(.~)`
- `Model.Core` — add `ComputationContext (ComputationContext)`, `Evaluator (Evaluator)`, `GameComputation (runGameComputation)`, `GameStateT (runGameStateT)`, `Narration (Narration)`, `NarrationMap (NarrationMap)`, `ctxPossibilityGraph`, `narrationMap`, `runEvaluator`, `unNarrationMap`, `evaluation`
- `Model.RichText` — add `plain`
- `Model.WireProtocol` — add `GameNarration`
- `Server.App` — add `acNextAgentId`, `succPInt`, `unPInt`

Remove dead imports from WorldAccum and processLeavesSF deletion.

### Module exports

```haskell
module Engine.Simulation.EffectNetwork
  ( RhineM
  , JoinResult (..)
  , gameLoop
  ) where
```

WorldAccum removed from exports.

## File 6: sashamud-world/src/SashaMudWorld.hs

Change `_evaluation = Evaluator eval` to `_evaluation = mempty`. Core.hs declares `_evaluation :: Map (GID Agent) Evaluator` — no players exist at startup; processOneJoin registers each player's evaluator at join. Remove the now-unused `Evaluator`/`eval` imports (verify against the actual file). This closes the Step 3c compile blocker that critique #3 identified but no plan owned.

## Lifecycle

1. **gameLoop** seeds accumulator with `Last (Just initialGameState)`
2. **Tick start** — deliverNarrationSF: `lookGameState`, send each player's narration via outbound, flush NarrationMap via `addGameState`
3. **Departures** — processLeavesSF: detect disconnected Denizens, remove from scenes, announce departures via NarrationMap, `addGameState`
4. **Joins** — processJoinsSF >-> executeJoinsSF: `lookGameState`, add players to scenes, announce arrival via NarrationMap, `addGameState`
5. **Input** — gatherInputSF >-> processInputSF: drain inbound, lex/parse text, `lookGameState`, run eval in GameComputation (StateT), `addGameState`
6. **Next tick** — deliverNarrationSF sends narration (departures + arrivals + game output) to all players who have it, flushes

## Why Last (Maybe GameState) + RhineM newtype

GameState with pure replacement (`_gs1 <> gs2 = gs2`) is NOT a lawful Monoid — right identity fails (`x <> mempty = mempty ≠ x`). AccumT depends on the Monoid laws: `lift` contributes `mempty`, and subsequent `look` sees `w <> mempty`. With broken right identity, `look` after `liftIO` returns `mempty` — the accumulated state gets wiped.

`Data.Monoid.Last` wraps `Maybe` to provide a lawful Monoid where `Last Nothing` is the identity (what lift/liftIO contribute). `Last (Just x) <> Last Nothing = Last (Just x)` — state preserved. The `Nothing` case is unreachable after gameLoop seeds the accumulator.

The RhineM newtype hides the Last/Maybe wrapping from all signal functions. `lookGameState` and `addGameState` handle the unwrapping internally. Signal functions never see `Last`, `Maybe`, `look`, or `add`.

MonadSchedule cannot be derived via newtype (Automaton's role for m is nominal). A manual instance uses `hoistS` to unwrap/rewrap, delegating to AccumT's existing instance.

## Files Touched

| File | Change |
|---|---|
| Model/Core.hs | Semigroup/Monoid for NarrationMap; FromJSON/ToJSON + TypeScript for Narration |
| Model/WireProtocol.hs | GameNarration [RichText] → GameNarration Narration; AnalysisViewport sum type replaces Text key in AnalysisData |
| Server/App.hs | PInt newtype (no constructor export); acNextAgentId :: IORef PInt |
| Engine/Evaluators/Player/General.hs | Delete sendMessage/getRecipients, fix eval stub |
| Engine/Simulation/EffectNetwork.hs | Delete WorldAccum, RhineM newtype with MonadSchedule + operations, rewrite all signal functions, add deliverNarrationSF + processLeavesSF + processInputSF bridge |
| sashamud-world/src/SashaMudWorld.hs | _evaluation = Evaluator eval → mempty (evaluators register per-player at join) |
