# Next Session Prompt

Read the plan at `/home/mlitchard/gitlab/sashamud/.claude-plans/remove-worldaccum.md` and execute it. This plan removes WorldAccum from EffectNetwork.hs and puts GameState into AccumT via `Data.Monoid.Last`, hidden behind a RhineM newtype.

Four files to change, in this order:

1. **Model/Core.hs** — Add Semigroup/Monoid instances for NarrationMap only (unionWith merge). GameState gets NO Semigroup/Monoid — `Data.Monoid.Last` provides the Monoid for AccumT. Add `unionWith` to Data.Map.Strict import.

2. **Server/App.hs** — Add `acNextAgentId :: IORef Int` to AppCtx, initialize to 1000 in newAppCtx via newIORef. Single-thread access — use `atomicModifyIORef'`.

3. **Engine/Evaluators/Player/General.hs** — Delete the broken sendMessage/getRecipients stubs. Rewrite evalStimulusVerbPhrase as a working stub that writes "the test worked!" narration to all PlayerAgent GIDs in the NarrationMap.

4. **Engine/Simulation/EffectNetwork.hs** — The big one:
   - Delete WorldAccum type, instances, and export. Delete processLeavesSF.
   - RhineM becomes a newtype over `AccumT (Last GameState) (ReaderT PossibilityGraph (ReaderT AppCtx IO))`.
   - Manual MonadSchedule instance: `schedule = fmap (hoistS unRhineM) >>> schedule >>> hoistS RhineM` (GND doesn't work — Automaton's role for m is nominal).
   - RhineM operations: `lookGameState`, `addGameState`, `askAppCtx`, `askPossibilityGraph` — these hide the Last/Maybe wrapping so signal functions never see it.
   - gameLoop seeds with `Last (Just gs)`, unwraps via `unRhineM`.
   - Restructure rhinePipeline to one sequential PlayerTick branch: `deliverNarrationSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF`.
   - All signal functions rewritten to use `lookGameState`/`addGameState`/`askAppCtx` instead of `look`/`add`/`lift (lift ask)`.
   - deliverNarrationSF: lookGameState, render narration via toPlainText, send via outbound, flush via addGameState.
   - processOneJoin: lookGameState, modify via lenses, announce arrival to all PlayerAgents in scene via NarrationMap, addGameState.
   - processInputSF: lookGameState, lexify tokens, parseTokens, run eval in GameComputation (unwrap StateT/ExceptT/ReaderT/Identity), addGameState.

Key design decisions already made:
- AccumT accumulates `Last GameState` (Data.Monoid.Last wraps Maybe) — lawful Monoid
- RhineM newtype hides the Last/Maybe — signal functions use lookGameState/addGameState
- Pure replacement on GameState fails right identity — look after liftIO returns mempty — that's why Last is needed
- Narration accumulates within a tick via StateT (GameComputation), flushes at next tick start via deliverNarrationSF
- All state-modifying signal functions sequential on one PlayerTick (parallel clock safety)
- GID counter lives in AppCtx IORef, not in the accumulator
- processOneJoin announces arrivals to all PlayerAgents in the scene via NarrationMap
- processInputSF does real lex/parse of input text, eval stub produces the test narration

Do NOT run builds or tests unless I ask. Read each file before editing.
