# Plan: Remove WorldAccum, GameState in AccumT via Last

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

### Import

Add `unionWith` to `Data.Map.Strict` import.

## File 2: Server/App.hs

Add `acNextAgentId :: IORef Int` to AppCtx. Initialize to 1000 in `newAppCtx` via `newIORef`. Single-thread access (one PlayerTick branch), no contention — IORef is the right primitive. Use `atomicModifyIORef'` to read and increment.

## File 3: Engine/Evaluators/Player/General.hs

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
  , AgentKind (PlayerAgent)
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
  let playerGids = keys (Data.Map.Strict.filter (\agent -> view agentKind agent == PlayerAgent) aMap)
      testNarration = Narration
        { _playerAction      = [colored White "the test worked!"]
        , _actionConsequence = []
        , _presenceListing   = []
        , _actionEpilogue    = []
        }
  forM_ playerGids $ \gid ->
    narrationMap . unNarrationMap . at gid .= Just testNarration
```

## File 4: Engine/Simulation/EffectNetwork.hs

### Delete

- WorldAccum type + Semigroup + Monoid instances + export
- processLeavesSF function

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
    (deliverNarrationSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF)
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

### deliverNarrationSF — reads narration, sends to players, flushes

```haskell
deliverNarrationSF :: ClSF RhineM (IOClock RhineM PlayerTick) () ()
deliverNarrationSF = constMCl $ do
  appCtx <- askAppCtx
  gs <- lookGameState
  pMap <- liftIO $ readMVar (acPlayerMap appCtx)
  let nMap = view (narrationMap . unNarrationMap) gs
  forM_ (assocs nMap) $ \(agentGid, narr) -> do
    let rendered = toPlainText
                     (mconcat (view playerAction narr)
                   <> mconcat (view actionConsequence narr)
                   <> mconcat (view presenceListing narr)
                   <> mconcat (view actionEpilogue narr))
        targetSids = [s | (s, g) <- assocs pMap, g == agentGid]
    forM_ targetSids $ \targetSid ->
      liftIO . atomically $
        writeTChan (acOutbound appCtx) (Routed targetSid (ChatMessage rendered))
  when (not (null nMap)) $
    addGameState (set narrationMap (NarrationMap mempty) gs)
```

### processJoinsSF

```haskell
processJoinsSF :: ClSF RhineM (IOClock RhineM PlayerTick) () [JoinResult]
processJoinsSF = constMCl $ do
  appCtx <- askAppCtx
  joins <- liftIO $ drainChan (acJoinChan appCtx)
  known <- liftIO $ readMVar (acKnownPlayers appCtx)
  traverse (processOneJoin known) joins
```

### executeJoinsSF — unchanged

### processOneJoin (returning player)

```haskell
processOneJoin known (PlayerJoined sid name) =
  case lookup name known of
    Just gid -> do
      gs <- lookGameState
      case lookup gid (view (world . agentMap . getAgentMap) gs) of
        Nothing -> pure ()
        Just agent -> do
          let sceneGid = view agentCurrentScene agent
          case lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs) of
            Nothing -> pure ()
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
                                     , Just a <- [lookup g aMap]
                                     , view agentKind a == PlayerAgent]
                  joinNarrations = Map.fromList [(g, announceNarration) | g <- recipientGids]
                  gs' = gs
                    & world . sceneMap . getGIDToDataMap . at sceneGid .~ Just scene'
                    & over (narrationMap . unNarrationMap) (Map.unionWith (<>) joinNarrations)
              addGameState gs'
      pure (ReturningPlayerJoined sid name gid)
```

### processOneJoin (new player)

```haskell
    Nothing -> do
      gs <- lookGameState
      appCtx <- askAppCtx
      nextId <- liftIO $ atomicModifyIORef' (acNextAgentId appCtx) (\n -> (n + 1, n))
      let gid = GID nextId
          lobbyGid = GID 0
          agent = mkPlayerAgent name lobbyGid
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
          existingPlayerGids = [g | g <- Set.toList (view sceneAgents lobby)
                                  , Just a <- [lookup g aMap]
                                  , view agentKind a == PlayerAgent]
          recipientGids = gid : existingPlayerGids
          joinNarrations = Map.fromList [(g, announceNarration) | g <- recipientGids]
          gs' = gs
            & world . agentMap . getAgentMap . at gid .~ Just agent
            & world . sceneMap . getGIDToDataMap . at lobbyGid .~ Just lobby'
            & over (narrationMap . unNarrationMap) (Map.unionWith (<>) joinNarrations)
      addGameState gs'
      pure (NewPlayerJoined sid name gid)
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
                    let ctx = ComputationContext { _ctxPossibilityGraph = pg }
                        comp = eval gid sentence
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

- `Control.Concurrent (modifyMVar_, readMVar)` — remove modifyMVar (no longer needed)
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
- `Engine.Evaluators.Player.General (eval)`
- `Lens.Micro.Platform` — add `at`, `over`, `set`, `(&)`, `(.~)`
- `Model.Core` — add `ComputationContext (ComputationContext)`, `GameComputation (runGameComputation)`, `GameStateT (runGameStateT)`, `Narration (Narration)`, `NarrationMap (NarrationMap)`, `ctxPossibilityGraph`, `narrationMap`, `unNarrationMap`, `evaluation`
- `Model.RichText` — add `toPlainText`
- `Server.App` — add `acNextAgentId`

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

## Lifecycle

1. **gameLoop** seeds accumulator with `Last (Just initialGameState)`
2. **Tick start** — deliverNarrationSF: `lookGameState`, send each player's narration via outbound, flush NarrationMap via `addGameState`
3. **Joins** — processJoinsSF >-> executeJoinsSF: `lookGameState`, add players to scenes, announce arrival via NarrationMap, `addGameState`
4. **Input** — gatherInputSF >-> processInputSF: drain inbound, lex/parse text, `lookGameState`, run eval in GameComputation (StateT), `addGameState`
5. **Next tick** — deliverNarrationSF sends narration to all players who have it, flushes

## Why Last (Maybe GameState) + RhineM newtype

GameState with pure replacement (`_gs1 <> gs2 = gs2`) is NOT a lawful Monoid — right identity fails (`x <> mempty = mempty ≠ x`). AccumT depends on the Monoid laws: `lift` contributes `mempty`, and subsequent `look` sees `w <> mempty`. With broken right identity, `look` after `liftIO` returns `mempty` — the accumulated state gets wiped.

`Data.Monoid.Last` wraps `Maybe` to provide a lawful Monoid where `Last Nothing` is the identity (what lift/liftIO contribute). `Last (Just x) <> Last Nothing = Last (Just x)` — state preserved. The `Nothing` case is unreachable after gameLoop seeds the accumulator.

The RhineM newtype hides the Last/Maybe wrapping from all signal functions. `lookGameState` and `addGameState` handle the unwrapping internally. Signal functions never see `Last`, `Maybe`, `look`, or `add`.

MonadSchedule cannot be derived via newtype (Automaton's role for m is nominal). A manual instance uses `hoistS` to unwrap/rewrap, delegating to AccumT's existing instance.

## Files Touched

| File | Change |
|---|---|
| Model/Core.hs | Semigroup/Monoid for NarrationMap only; no GameState instances needed |
| Server/App.hs | acNextAgentId :: IORef Int |
| Engine/Evaluators/Player/General.hs | Delete sendMessage/getRecipients, fix eval stub |
| Engine/Simulation/EffectNetwork.hs | Delete WorldAccum + processLeavesSF, RhineM newtype with MonadSchedule + operations, rewrite all signal functions, add deliverNarrationSF + processInputSF bridge |
