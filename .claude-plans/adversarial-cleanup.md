# Plan: adversarial cleanup of the per-tick monolith

STATUS: APPROVED

## Context

Adversarial review of the monolith work (2026-07-13) found seven violations of the design, minor to major.
This plan fixes all of them, minor first, major last. One file changes throughout: `sasha/src/Engine/Simulation/SignalNetwork.hs`.

## Gate

Every step ends with the user running `nix flake check`. Claude never builds. A step is done when the check
passes; compiler errors come back as the next prompt. No step starts before the previous one passes.

## Step 1 (minor): inline processAutoLook

Delete `processAutoLook` (single-call one-liner helper — violates "no helpers"). At its call site in `composeTick`:

```haskell
  forM_ (successfulJoinGIDs joinResults) $ \gid -> runEvalFor gid "look"
```

## Step 2 (minor): unify state discipline in processLeavesPure

Leaves use `get` + per-scene `modify` with stale closures; joins use `get`/`put`. Unify on `get`/`put`: fold the departures into one new state, single `put`.

```haskell
processLeavesPure sessions known = do
  gs <- get
  let activeGids = ...            -- unchanged
      knownGids  = ...            -- unchanged
      aMap       = ...            -- unchanged
      isDeparted = ...            -- unchanged
      sceneDepartures = ...       -- unchanged
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
```

`modify` import: check remaining uses; if none, drop it from the `Control.Monad.State` import list.

## Step 3: rename successfulJoinGIDs → joinGIDs

The name lies — failures throw and kill the tick, so every JoinResult is a success. Pure rename, all sites (definition + the Step 1 call site).

## Step 4: drop the dead name field from ReturningPlayerJoined

`ReturningPlayerJoined SessionId PlayerNameVAL (GID Agent)` — the `PlayerNameVAL` is ignored by every consumer (`joinComputation` `_name`, `executeJoinIO` `_name`). Constructor becomes:

```haskell
data JoinResult = NewPlayerJoined SessionId PlayerNameVAL (GID Agent)
                | ReturningPlayerJoined SessionId (GID Agent)
```

Update: `classify` (`ReturningPlayerJoined sid gid`), `joinComputation (ReturningPlayerJoined _sid gid)`, `joinGIDs` (`ReturningPlayerJoined _ gid -> gid`),
`executeJoinIO ctx (ReturningPlayerJoined sid gid)`.

RULED (user, 2026-07-13): drop `JoinResult (..)` from the export list in this step — nothing outside SignalNetwork.hs uses it.

## Step 5: delete the JoinFailure ceremony

Four constructors + `joinFailureText`, immediately squashed to Text at `throwError`, while sibling throws in the same file use inline `"Programmer Error: ..."` Text. Delete `JoinFailure` and `joinFailureText`; inline house-style texts at the four throw sites:

```haskell
throwError ("Programmer Error: returning player agent not found: " <> pack (show gid))
throwError ("Programmer Error: returning player location not found: " <> pack (show gid))
throwError ("Programmer Error: returning player scene not found: " <> pack (show sceneGid))
throwError ("Programmer Error: new player start scene not found: " <> pack (show sceneGid))
```

Noted: MEMORY records a future cut to `ExceptT GameError` sum types — when that lands, these texts become constructors like every other throw in the file. Until then, one style per file.

## Step 6: PossibilityGraph through the Reader, not a parameter

`GameComputation` derives `MonadReader ComputationContext` (Core.hs:334) and `ComputationContext` carries `_ctxPossibilityGraph` 
— the `pg` parameter into `processJoinsPure` is a second authority for the same value. `Lens.Micro.Platform`
re-exports the MonadReader-polymorphic `view` (Lens.Micro.Mtl), the same family as the `use` already in this file.

- `processJoinsPure :: Map PlayerNameVAL (GID Agent) -> [(PlayerJoined, GID Agent)] -> ([JoinResult], GameComputation Identity ())` — `pg` gone
- In `joinComputation (NewPlayerJoined ...)`:

```haskell
      pg <- view ctxPossibilityGraph
      let sceneGid = view newUserStartScene pg
          mkAgent  = view newUserMkAgent pg
```

- `composeTick` drops its `pg` parameter (it only forwarded it)
- Imports: add `ctxPossibilityGraph` to the Model.Core list. `playerTickBlock` still uses `pg` to build `ComputationContext` — unchanged.

## Step 7 (major): composeTick becomes a pure sequencer; joinResults at generation time

Findings 1+2: `joinResults` depends only on `known`+`newGIDs` (zero GameState) yet rides through the executed computation's return value; and composeTick is half sequencer, half generator-caller. Fix both at once — all generators run in `playerTickBlock`'s let, composeTick only sequences:

```haskell
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
```

`playerTickBlock`:

```haskell
  let (pings, commandComp) = resolveCommands sessions msgs
      (joinResults, joinComp) = processJoinsPure known newGIDs
      leavesComp = processLeavesPure sessions known
      ctx = ComputationContext { _ctxPossibilityGraph = pg }
      tickComp = composeTick leavesComp joinComp commandComp (joinGIDs joinResults)
      (result, gs') = runPureComputation tickComp ctx gs
```

Result handling — `joinResults` is generation-time data now, but `executeJoinIO` stays gated on `Right` (a failed tick must not promote sessions or send welcomes):

```haskell
  case result of
    Left err ->
      liftIO $ hPutStrLn stderr ("Tick computation failed: " <> unpack err)
    Right narrations -> do
      liftIO $ forM_ joinResults (executeJoinIO appCtx)
      liftIO $ deliverNarrationIO appCtx narrations
```

## Memory (after all steps pass)

Update `.claude-memory/MEMORY.md`: generators run at the generation site (playerTickBlock let); the sequencer takes only computations and generation-time data — never raw maps to re-generate from; data that doesn't depend on GameState never routes through the executed computation's return value.

## Verification

`nix flake check` after every step. Runtime behavior identical at every step: join/leave announcements, auto-look, command narration, ping/pong.
