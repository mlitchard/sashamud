# Same-tick join: a command sent in the tick of its own join resolves to its actor

## Goal

`sashamud-server/test-e2e/SlmRepairSpec.hs` "an unparseable sentence is repaired by the model and runs" passes in the e2e suite in the main checkout, with the test left as written.

## The fault (witnessed 2026-10-22)

`nix log` of vm-test-run-sasha-end-to-end, line 1285: `TickFailed (SessionMissing (SessionId ...))`.

The test types its sentence the moment the bridge reads "connected", so the PlayerJoined and the GameCommand land in the same PlayerTick. `playerTickBlock` reads `acSessions` once at its start (SignalNetwork.hs:292), when the session is still `AwaitingJoin`. `sessionGid` is `Just` only for `InGame` (App.hs:90-93). The repair grammar's actor lookup, `actorVerbs` (SignalNetwork.hs:619-626), and the ordinary command lookup, `commandComputation` (SignalNetwork.hs:606-609), both do `lookup sid sessions >>= sessionGid`, find `Nothing`, and throw `SessionMissing`. The whole tick fails, join included. `executeJoinIO` (SignalNetwork.hs:776) runs only after a successful tick, so the session never becomes `InGame`; a reconnect while `AwaitingJoin` queues no new join (GameWebSocket.hs:28-30). Narration and heartbeats go only to sessions with a `Just` gid, so the browser sees nothing for 300 s.

Before this branch the grammar came from the sentence and player names alone, so building the RepairRequest never looked the actor up. The branch's step that narrows the grammar to the actor's verbs added the lookup, and the same-tick case became fatal.

## What exists today

- `playerTickBlock` (SignalNetwork.hs:287): reads `sessions`, drains `joins` and `msgs`, calls `resolveCommands sessions pending playerLookup msgs`, builds `f gs` with `processJoinsPure` and `composeTick`, and on `Right` runs `executeJoinIO` for every join result, then `deliverNarrationIO`.
- `composeTick` (SignalNetwork.hs:379): runs `leavesComp`, then `joinComp`, then `commandComp`, then the auto-look for joined gids. The joiner's agent is in the agent map before any command runs.
- `PlayerJoined sid name gid` (API.Types) carries the session's GID. `SessionPhase PlayerNameVAL (GID Agent) SessionState` (App.hs:76) carries it in every state.
- `resolveCommands` (SignalNetwork.hs:538) takes `sessions`, `pending`, `playerLookup`, `msgs`. Its export is used by `SignalNetworkSpec.hs` (three tests, line 95 on) with an `InGame` session.
- `runPureComputation` runs a `GameComputation Identity a` against a `GameState` and returns the result with the new state (used at SignalNetwork.hs:318). It is unexported.

## Old-code precedent

None. The old code is single-player and has no sessions. sashamud's own rulings govern: the generator pattern (2026-07-13), "is-connected-now: acSessions InGame phase", and "never swallow errors in the signal pipeline".

## Decisions

D1. Actor source for a command in a tick. RULED (user, 2026-10-22): the session's `InGame` GID, else the GID of this tick's `PlayerJoined` for that session. `sessionGid` keeps its meaning. The join computation runs before the command computation in `composeTick`, so the agent exists when the command runs. A session that is `AwaitingJoin` with no join in this tick still throws `SessionMissing`, as today.

D2. Where the same-tick pairs are built. RULED (user, 2026-10-22): in `playerTickBlock` from `joins`, as `Map SessionId (GID Agent)`, and passed to `resolveCommands` as a new parameter after `sessions`. The pairs depend on no GameState, so they are generation-time data, which the generator pattern says belongs at the generation site.

D3. The e2e test stays as written. RULED (user, 2026-10-22). It is the witness for the same-tick case.

D4. MEMORY.md Design Decisions: the line beginning "MVar reads" says processInputSF reads acSessions post-join and the first command routes same-tick. RULED (user, 2026-10-22): restate it to the current shape once step 1 is green (Sonnet, spec shown first).

## Steps

Step rule: every step builds and is green on its own. Every fix a step needs, including imports, exports, callers and tests, lands in that step.

### Step 1. resolveCommands learns this tick's joins

`sasha/src/Engine/Simulation/SignalNetwork.hs`

- Export list: add `runPureComputation`.
- `resolveCommands` signature: insert `-> Map SessionId (GID Agent)` after the `Map SessionId SessionPhase` argument. Binding becomes `resolveCommands sessions joining pending playerLookup msgs`.
- In its `where`, add one binding beside `found`:
  ```haskell
  actorGid sid = case lookup sid sessions >>= sessionGid of
    Just gid -> Just gid
    Nothing  -> lookup sid joining
  ```
- `commandComputation`: `case actorGid sid of` in place of `case lookup sid sessions >>= sessionGid of`.
- `actorVerbs`: the `actor` binding becomes
  ```haskell
  let actor = do
        gid <- actorGid sid
        lookup gid aMap
  ```
- `playerTickBlock`: after `msgs <- ...`, add
  ```haskell
  let joining = fromList [(sid, gid) | PlayerJoined sid _ gid <- joins]
  ```
  and the call becomes `resolveCommands sessions joining pending playerLookup msgs`. `PlayerJoined` is already imported for `processJoinsPure`; `fromList` is already in use in the file.

`sasha/test/SignalNetworkSpec.hs`

- The three existing `resolveCommands` calls gain `mempty` as the second argument.
- Imports: `SessionState (AwaitingJoin, InGame)`; `runPureComputation` from `Engine.Simulation.SignalNetwork`; `MessageFrom (AnalysisData, RepairRequest)` from `Model.WireProtocol`; `show` from `SashaPrelude` if it is exported there (the writer reads the prelude export list).
- New test in the `describe "resolveCommands"` block:
  ```haskell
  it "resolves a command from a session whose join lands in the same tick" $ do
      let joiningSessions = fromList [(sid, SessionPhase (PlayerNameVAL "tester") playerGid (AwaitingJoin (const (pure ()))))]
          joining = fromList [(sid, playerGid)]
          (_, _, _, _, _, comp) = resolveCommands joiningSessions joining mempty (PlayerWordsFound mempty) [Routed sid (GameCommand "look look")]
      case runPureComputation comp gs of
          (Left err, _) -> expectationFailure (show err)
          (Right [Routed target (RepairRequest {})], _) | target == sid -> pure ()
          (Right _, _) -> expectationFailure "expected one repair request for the joining session"
  ```
  Before the change this test is `Left (SessionMissing sid)`. After it, the repair request is built for the joining session.

Green means: `sasha-tests` passes with the new test, and the e2e suite passes with SlmRepair enabled.

### Step 2. Record the ruling

MEMORY.md Design Decisions, the "MVar reads" line: replace the clause "processInputSF reads acSessions post-join (executeJoinsSF promotes AwaitingJoin → InGame mid-tick, new player's first command routes same-tick)" with "playerTickBlock reads acSessions once at tick start; a command whose join lands in the same tick resolves its actor through that tick's PlayerJoined gid (resolveCommands `joining`); executeJoinIO promotes AwaitingJoin → InGame after the tick succeeds, before deliverNarrationIO". Sonnet writer, spec shown in chat first.
