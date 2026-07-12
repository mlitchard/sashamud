# Next Session Prompt

Read the plan at `/home/mlitchard/gitlab/sashamud/.claude-plans/remove-worldaccum.md`
and execute it. This plan removes WorldAccum from SignalNetwork.hs and puts GameState into AccumT via `Data.Monoid.Last`, hidden behind a RhineM newtype.

Six files to change, in this order:

1. **Model/Core.hs** — Add Semigroup/Monoid instances for NarrationMap (unionWith merge).
Add FromJSON/ToJSON to Narration's anyclass deriving. Add `derivingTypeScriptDefinition
''Narration` in the TH section. GameState gets NO Semigroup/Monoid. Add `unionWith` to
Data.Map.Strict import.

2. **Model/WireProtocol.hs** — Change `GameNarration [RichText]` to `GameNarration Narration`
. Add `Narration` to the import from Model.Core.
Add `AnalysisViewport = Parser | State | Meta | Graphics | GameMap`
(Bounded/Enum/Eq/Generic/Ord/Show stock; FromJSON/FromJSONKey/NFData/ToJSON/ToJSONKey
anyclass) and change `AnalysisData (Map Text [RichText])` to
`AnalysisData (Map AnalysisViewport [RichText])`. Export it, add derivingTypeScriptDefinition, add TESTING Arbitrary via GenericArbitrary.

3. **Server/App.hs** — Add the PInt newtype (hidden constructor; exports only
`succPInt`, `unPInt`, `firstPlayerId` — no typeclasses) and `acNextAgentId :: IORef PInt` to AppCtx, initialize to `firstPlayerId` (1000) in newAppCtx via newIORef. Single-thread access — `atomicModifyIORef'` with `succPInt`; mint GIDs via `GID (unPInt p)`.

4. **Engine/Evaluators/Player/General.hs** — Delete the broken sendMessage/getRecipients stubs. Rewrite evalStimulusVerbPhrase as a working stub that writes "the test worked!" narration to all Denizen GIDs in the NarrationMap.

5. **Engine/Simulation/SignalNetwork.hs** — The big one:
   - Delete WorldAccum type, instances, and export. Replace old processLeavesSF with new implementation.
   - RhineM becomes a newtype over `AccumT (Last GameState) (ReaderT PossibilityGraph (ReaderT AppCtx IO))`.
   - Manual MonadSchedule instance: `schedule = fmap (hoistS unRhineM) >>> schedule >>> hoistS RhineM`.
   - RhineM operations: `lookGameState`, `addGameState`, `askAppCtx`, `askPossibilityGraph`.
   - gameLoop seeds with `Last (Just gs)`, unwraps via `unRhineM`.
   - Restructure rhinePipeline to one sequential PlayerTick branch: `deliverNarrationSF >-> processLeavesSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF`.
   - deliverNarrationSF: lookGameState, send `GameNarration narr` per player via outbound, flush NarrationMap, output the tick's acPlayerMap snapshot to processLeavesSF.
   - processLeavesSF: consume the threaded acPlayerMap snapshot (no re-read), detect departed players session-based (gid in acKnownPlayers, absent from acPlayerMap — NEVER via AgentKind, NPCs are Denizens too), remove from scenes, announce departures via NarrationMap, output the acKnownPlayers snapshot to processJoinsSF.
   - processOneJoin: lookGameState, modify via lenses, announce arrival to other Denizens (exclude joiner), register evaluator, addGameState.
   - processInputSF: lookGameState, lexify tokens, parseTokens, look up evaluator per agent from `view evaluation gs`, run in GameComputation, addGameState.

6. **sashamud-world/src/SashaMudWorld.hs** — Change `_evaluation = Evaluator eval` to `_evaluation = mempty` (Core.hs declares `Map (GID Agent) Evaluator`; evaluators register per-player at join). Remove now-unused imports — verify against the actual file.

Key design decisions already made:
- AccumT accumulates `Last GameState` (Data.Monoid.Last wraps Maybe) — lawful Monoid
- RhineM newtype hides the Last/Maybe — signal functions use lookGameState/addGameState
- MonadSchedule manual instance via hoistS (GND doesn't work)
- GameNarration carries structured Narration (not flattened [RichText])
- Narration accumulates within a tick via StateT (GameComputation), flushes at next tick start
- All state-modifying signal functions sequential on one PlayerTick
- GID counter is `IORef PInt` in AppCtx — PInt is a bare newtype with hidden constructor, only succPInt/unPInt/firstPlayerId exported; subtraction is impossible by export list, not by typeclass
- processInputSF looks up evaluator per agent from GameState, sends "failure to load evaluator" if missing
- processOneJoin registers Evaluator eval for new players, excludes joiner from arrival narration
- Join failures are a sum type: JoinFailure (ReturningAgentMissing | ReturningSceneMissing) inside JoinError, rendered by joinFailureText only at the display boundary (executeJoinsSF → SystemMessage) — the signal chain never carries naked Text in an Either
- processLeavesSF departure detection is session-based: gid in acKnownPlayers AND absent from acPlayerMap — AgentKind never proxies for "is a player"
- One MVar read per tick phase, threaded via >-> : deliverNarrationSF reads acPlayerMap once → processLeavesSF; processLeavesSF reads acKnownPlayers once → processJoinsSF; processInputSF makes the only post-join acPlayerMap read (new player's first command must route same-tick). No SF re-reads an MVar another SF already read.
- AgentKind uses Denizen (not PlayerAgent — that was invented)
- Eval stub writes "the test worked!" to all Denizens — real dispatch is next build

Do NOT run builds or tests unless I ask. Read each file before editing.
