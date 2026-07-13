# Plan: Per-Tick Monolith via Composition

**STATUS: APPROVED**

## Problem

Current architecture runs each player command through a full cycle:
1. `lookGameState` — pull GameState from AccumT
2. Construct `ComputationContext`
3. Generate `GameComputation Identity ()` — evaluator produces the computation
4. `runIdentity . runStateT gs . runGameStateT . runExceptT . runReaderT ctx . runGameComputation` — execute it
5. `addGameState gs'` — push result to AccumT

With N commands per tick, that's N AccumT round-trips, N ComputationContext constructions, and N transformer teardowns.
Steps 3 and 4 are the generation/execution boundary — that boundary is architecturally valuable and must be preserved.

## Solution

Collapse the six sequential ClSFs on the PlayerTick clock into a single `constMCl` block.
**Compose** all generated `GameComputation Identity ()` values into one big computation
using monadic `>>`, then run it once. The generation/execution boundary is preserved —
evaluators still generate pure computation values, and the monolith executes the composed result.

`GameComputation Identity ()` is a Monad. `comp1 >> comp2` threads state: `comp2` sees the GameState left by `comp1`. This is the `StateT` bind contract.

## Error Model

ExceptT in GameComputation captures **programmer errors** — data inconsistency that should never
occur in a functioning system (missing evaluator, missing agent in agentMap, missing scene). These are game-breaking. If one fires:

- Rolling back does not matter — the world is inconsistent
- Processing other commands does not matter — subsequent commands operate on broken state
- The first error aborts the composition via ExceptT short-circuit

Game logic responses ("I don't understand that", scene descriptions, presence listings) are **narration**,
not exceptions. They flow through NarrationMap as normal state modifications. There is no per-command error
isolation because there are no per-command recoverable errors.

Error evaluation happens **after** the composed computation executes, not per-composition:

```haskell
let (result, gs') = runPureComputation composedComp ctx gs
case result of
  Left err -> liftIO $ hPutStrLn stderr ("Tick failed: " <> err)
  Right (joinResults, narrations) -> ...
```

## Tick Structure

```
┌─ IO Phase: gather inputs ──────────────────────────────┐
│  readMVar acSessions, acKnownPlayers                   │
│  drainChan acJoinChan, acInbound                       │
│  pre-allocate GIDs for new players (atomicModifyIORef) │
│  lex/parse commands, resolve session→GID               │
│  → [(GID, Sentence)] for pure phase                    │
│  → Map GID SessionId for narration routing             │
│  lex/parse failures sent immediately (no GameState)    │
└────────────────────────────────────────────────────────-┘
                         │
                         ▼
┌─ Generation Phase: compose one GameComputation ────────┐
│  processLeavesPure sessions known                      │
│  >> processJoinsPure known joinsWithGIDs               │
│  >> forM_ resolvedCmds (uncurry runEvalFor)            │
│  >> processAutoLook joinedGIDs                         │
│  >> extractNarration                                   │
│  No SessionId — pure computation works with GIDs only  │
│  No catchError — ExceptT errors are game-breaking      │
│  Result: ([JoinResult], Map (GID Agent) Narration)     │
└────────────────────────────────────────────────────────-┘
                         │
                         ▼
┌─ Execution Phase: run once ────────────────────────────┐
│  runPureComputation composedComp ctx gs                │
│  → (Either Text ([JoinResult], narrationMap), gs')     │
│  Left = programmer error, log it                       │
│  Right = success, proceed to IO effects                │
│  One ComputationContext. One StateT. One teardown.     │
└────────────────────────────────────────────────────────-┘
                         │
                         ▼
┌─ IO Phase: apply effects ──────────────────────────────┐
│  executeJoinsIO (session promotion, welcome messages)  │
│  deliver narrations: GID → SessionId, send to clients  │
│  addGameState gs' — one AccumT push                    │
└────────────────────────────────────────────────────────-┘
```

## Evaluator Invocation

Inside the composed computation, each command invokes its evaluator directly — no wrapping, no error catching:

```haskell
runEvalFor :: GID Agent -> Sentence -> GameComputation Identity ()
runEvalFor gid sentence = do
  evaluator <- lookupEvaluatorOrThrow gid
  _runEvaluator evaluator gid sentence

lookupEvaluatorOrThrow :: GID Agent -> GameComputation Identity Evaluator
lookupEvaluatorOrThrow gid = do
  evals <- use evaluation
  case lookup gid evals of
    Nothing -> throwError ("Programmer Error: no evaluator for " <> pack (show gid))
    Just evaluator -> pure evaluator
```

If `lookupEvaluatorOrThrow` fires, ExceptT short-circuits. The composition aborts. The caller sees `Left`. This is correct — a missing evaluator means the world is broken.

## Auto-Look: Direct Composition

Current auto-look works by injecting `GameCommand "look"` into acInbound and re-draining. The monolith replaces it with direct composition:

```haskell
processAutoLook :: [GID Agent] -> GameComputation Identity ()
processAutoLook joinedGids =
  forM_ joinedGids $ \gid ->
    case lexify tokens "look" of
      Left _ -> pure ()
      Right lexemes -> case parseTokens lexemes of
        Left _ -> pure ()
        Right sentence -> runEvalFor gid sentence
```

Same pipeline as any player command — lex, parse, eval. Narration lands in the NarrationMap and is delivered at the end of the tick. No channel injection, no re-drain.

## Narration Extraction

The pure computation extracts the narration data and clears the NarrationMap:

```haskell
extractNarration :: GameComputation Identity (Map (GID Agent) Narration)
extractNarration = do
  nMap <- use (narrationMap . unNarrationMap)
  narrationMap .= NarrationMap mempty
  pure nMap
```

The IO phase routes each narration to the right client via GID → SessionId lookup. The stored GameState has narration cleared.

## runPureComputation

Extract the existing inline teardown as a named function (matches the old sasha-server pattern):

```haskell
runPureComputation :: GameComputation Identity a
                   -> ComputationContext -> GameState
                   -> (Either Text a, GameState)
runPureComputation comp ctx gs =
  let action = runExceptT (runReaderT (runGameComputation comp) ctx)
  in runIdentity $ runStateT (runGameStateT action) gs
```

Called once per tick. `Left` = programmer error (missing evaluator, missing agent, missing scene). `Right` = all commands executed, narration ready for delivery.

## Multi-Clock Safety

The monolith is per-clock. Each clock gets its own block:

```
AccumT (Last GameState)   ← the behavior, shared across all clocks
        │
        ├── PlayerTick block:
        │     lookGameState → IO reads → compose → runPureComputation → IO effects → addGameState
        │
        ├── (future clocks follow same pattern)
        │
        └── HeartbeatTick: read-only, no state modification
```

MonadSchedule serializes step execution (one worker per step via MVar). Two clocks never race on AccumT.

---

## File Changes

### Engine/Simulation/SignalNetwork.hs — major restructure

**Add** `runPureComputation` (extracted from current `runCommand` inline code).

**Add** `runEvalFor` and `lookupEvaluatorOrThrow`.

**Add** `playerTickBlock` — single `constMCl` replacing the six composed ClSFs:

```haskell
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

  -- IO: resolve commands — lex/parse, map session→GID
  -- Lex/parse failures sent as error messages immediately (no GameState impact)
  -- Returns [(GID, Sentence)] for the pure phase
  (resolvedCmds, gidToSid) <- liftIO $ resolveCommands appCtx sessions msgs

  let ctx = ComputationContext { _ctxPossibilityGraph = pg }

  -- GENERATE: compose one big GameComputation
  let tickComp = composeTick sessions known newGIDs resolvedCmds pg

  -- EXECUTE: run once
  let (result, gs') = runPureComputation tickComp ctx gs

  -- ERROR EVALUATION: after execution
  case result of
    Left err ->
      -- Programmer error — world is inconsistent
      liftIO $ hPutStrLn stderr ("Tick computation failed: " <> err)
    Right (joinResults, narrations) -> do
      -- IO: execute join effects (session promotion, welcome messages)
      liftIO $ forM_ joinResults (executeJoinIO appCtx)
      -- IO: deliver narrations to clients via GID → SessionId
      liftIO $ deliverNarrationIO appCtx sessions gidToSid narrations

  addGameState gs'
```

**Add** `composeTick` — the composition function. No SessionId, no error collection, no catchError:

```haskell
composeTick :: Map SessionId SessionPhase
            -> Map PlayerNameVAL (GID Agent)
            -> [(PlayerJoined, GID Agent)]
            -> [(GID Agent, Sentence)]
            -> PossibilityGraph
            -> GameComputation Identity ([JoinResult], Map (GID Agent) Narration)
composeTick sessions known newGIDs resolvedCmds pg = do
  processLeavesPure sessions known
  joinResults <- processJoinsPure known newGIDs pg
  forM_ resolvedCmds (uncurry runEvalFor)
  processAutoLook (successfulJoinGIDs joinResults)
  narrations <- extractNarration
  pure (joinResults, narrations)
```

**Refactor** current SF bodies into pure GameComputation functions:

- `processLeavesPure` — current processLeavesSF logic, uses `get`/`modify` instead of lookGameState/addGameState
- `processJoinsPure` — current processOneJoin logic (without IO parts), returns JoinResult list
- `processAutoLook` — direct composition of look computation for joined players
- `extractNarration` — reads NarrationMap, clears it, returns the map

**Add** IO helper functions:

- `allocateNewGIDs` — atomicModifyIORef' for each new player
- `resolveCommands` — lex/parse and session→GID lookup; returns `[(GID Agent, Sentence)]` for the pure computation and a `Map (GID Agent) SessionId` for routing narrations in the IO phase. Lex/parse failures are handled immediately via IO (writeTChan error message) since they don't touch GameState
- `executeJoinIO` — session promotion (modifyMVar_ acSessions), welcome messages (writeTChan)
- `deliverNarrationIO` — route narrations to clients via acOutbound, using GID → SessionId mapping

**Remove**: processLeavesSF, processJoinsSF, executeJoinsSF, gatherInputSF, processInputSF, deliverNarrationSF, runCommand, tryCommand (never existed in code, removed from plan).

**Update** `rhinePipeline`:
```haskell
rhinePipeline =
    heartbeatSF       @@ ioClock (waitClock :: HeartbeatTick)
    |@|
    playerTickBlock   @@ ioClock (waitClock :: PlayerTick)
```

**Import changes**:
- Remove: `(>->)` from FRP.Rhine import, `Control.Monad.Error.Class (catchError)` (not needed)
- Keep: `runExceptT`, `runStateT`, `runIdentity`, `runGameComputation`, `runGameStateT`

### No other files change

| File | Status |
|------|--------|
| Model/Core.hs | Untouched — `GameComputation Identity ()` preserved |
| Engine/Evaluators/Player/General.hs | Untouched |
| Engine/ActionDiscovery/*.hs | Untouched |
| Engine/Resolution/*.hs | Untouched |
| ConstraintRefinement/Actions.hs | Untouched |
| SashaMudWorld.hs | Untouched |
| Server/*.hs | Untouched |
| sasha.cabal | Untouched |

---

## What This Preserves

- **Generation/execution separation**: evaluators produce `GameComputation Identity ()` values. `composeTick` assembles them with `>>`. `runPureComputation` executes the assembly. Generation and execution are distinct phases.
- **Pure computation representation**: `GameComputation Identity ()` is a reifiable value — storable, composable, testable against arbitrary GameStates. Critical for the sequenced effect system (generate on PlayerTick, store, execute on SequenceTick).
- **ExceptT for programmer errors only**: missing evaluator, missing agent, missing scene — data inconsistency that should never happen. Error evaluation happens after execution, not during composition.
- **SessionId stays in the IO phase**: the pure computation works with GIDs. A `Map (GID Agent) SessionId` built during command resolution routes narrations to clients in the IO phase. SessionId never leaks into GameComputation.
- **Narration delivery**: narration accumulates in the NarrationMap during the pure computation (same as now), extracted and delivered via IO at the end.

## What This Eliminates

- **Per-command AccumT round-trip**: one `lookGameState` + one `addGameState` per tick instead of per command
- **Per-command ComputationContext construction**: built once, passed to `runPureComputation`
- **Per-command transformer teardown**: one `runPureComputation` call per tick instead of per command
- **Per-command error handling**: no tryCommand, no catchError, no snapshot/rollback — ExceptT errors are game-breaking, evaluated once after execution
- **Channel injection hack for auto-look**: direct composition replaces the acInbound round-trip

## Future Clocks

The per-clock monolith pattern (IO reads → compose `GameComputation Identity` → `runPureComputation` once → IO effects → `addGameState`) extends to additional clocks when the sequenced effect system arrives. The same `GameComputation Identity ()` representation used by evaluators works for effect computations on other clocks — compose with `>>`, run once, deliver narration. Clock names, types, and structure are not specified here.
