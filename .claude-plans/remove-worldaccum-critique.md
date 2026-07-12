# Critique: remove-worldaccum plan

Adversarial review of `/home/mlitchard/gitlab/sashamud/.claude-plans/remove-worldaccum.md`,
verified against the actual code and the Rhine source. Problems numbered — address one at a time.

## Verified sound (no action needed)

- The Monoid law argument is correct: pure replacement (`_x <> y = y`) fails right identity,
  AccumT depends on it (`lift` contributes `mempty`), `Last` fixes it lawfully.
- `instance (Monoid w, ...) => MonadSchedule (AccumT w m)` exists —
  rhine/automaton/src/Data/Automaton/Schedule.hs:213. `hoistS` exists — Data/Automaton.hs:313.
  The manual RhineM instance shape matches the FinalizeT precedent (Schedule.hs:176-187).
- processInputSF unwrap order is exact for
  `GameComputation = ReaderT ComputationContext (ExceptT Text (GameStateT m))` (Core.hs:310),
  `GameStateT = StateT GameState` (Core.hs:289).
- eval pattern matches are total: Sentence/Imperative/StimulusVerbPhrase are single-constructor
  (sasha-grammar Composites/Model.hs:17-27), constructor names match old code.
- Single sequential writer branch on PlayerTick is the right call.
- `toPlainText` and RichText Semigroup/Monoid exist (RichText.hs:92-99).
- Lifecycle (deliver → flush → joins → input → next-tick deliver) has no narration-loss window.

## Problems

### 1. WITHDRAWN — Narration's Semigroup/Monoid is real

Original claim: bare `deriving (Monoid, Semigroup)` at Core.hs:217 is an empty anyclass
instance. WRONG — the review grep truncated at line 217; line 218 reads
`via (Generically Narration)`. DerivingVia through Generically gives lawful field-wise
`<>` (list concatenation per field) and field-wise `mempty`. No action needed.

Why the instances exist (for the record):
- Semigroup: NarrationMap's `unionWith (<>)` merges two Narrations when two events
  target the same player in one tick
- Monoid: `non mempty` in modifyAgentNarration (Perception.hs:39) — insert-or-update
  for players with no narration entry yet

### 2. RESOLVED — Denizen | Fixture is correct; PlayerAgent was an invention

User verdict: the data type (`Denizen | Fixture`, Core.hs:145-148) is correct. Old code
confirms: SashaLambdaDSL.hs:710 "Denizen for characters, Fixture for object-agents";
old Server.hs:218 creates player agents with `_agentKind = Denizen` and filters players
on `== Denizen` (Server.hs:183).

Fixed (PlayerAgent → Denizen): Core.hs:7 export (also FixtureAgent → Fixture),
Engine/Resolution/ActionManagement.hs, Engine/Resolution/Perception.hs,
Engine/Simulation/SignalNetwork.hs, sashamud-world SashaMudWorld.hs and
test/DSL/BuilderSpec.hs, and the plan document's code blocks.

Discovered while fixing, moved to #3's scope: SashaMudWorld.hs:67 sets
`_evaluation = Evaluator eval` (single Evaluator) but Core.hs:285 declares
`_evaluation :: Map (GID Agent) Evaluator` — type mismatch.

### 3. RESOLVED — `_evaluation` field now used properly

- Code says: `_evaluation :: Map (GID Agent) Evaluator` (Core.hs:285) — this is correct
- Plan: processInputSF looks up evaluator per agent via `view evaluation gs`,
  sends "failure to load evaluator" if not found. processOneJoin registers
  `Evaluator eval` for new players via `evaluation . at gid .~ Just (Evaluator eval)`
- SashaMudWorld.hs:67 assigns `_evaluation = Evaluator eval` (single Evaluator) —
  type mismatch, should be `mempty` (no players at startup). Pre-existing Step 3c
  compilation issue, outside this plan's scope.

### 4. RESOLVED — no stale-read hazard

The IO MonadSchedule (Schedule.hs:109-120) uses one input MVar and one output MVar.
Each combined step: put ONE input → ONE worker takes it, steps, puts output → main takes
output. Workers interleave via MVar — they never run simultaneously. Each worker's
contribution is folded into the accumulated state before the next worker runs.

The scenario "stale read then clobber" requires two branches reading the same snapshot
concurrently. This can't happen because: (1) MVar serialization means one worker per step,
(2) HeartbeatSF contributes `Last Nothing` — it never overwrites state, (3) all
state-modifying SFs are on one sequential PlayerTick chain via `>->`.

Verified by tracing: AccumT decomposes into Reader (state in) + Writer (contribution out)
for scheduling. The Reader environment is updated after each step. The IO scheduler's
interleaving ensures each step sees the latest accumulated state.

### 5. RESOLVED — stub is user-approved, no-stubs rule applies to Claude only

User directive: the no-stubs rule in CLAUDE.md constrains Claude, not the user. The user
approved the "the test worked!" stub for this build. The goal is to verify the full
pipeline (lex → parse → eval → GameComputation → NarrationMap → delivery). Real dispatch
via manageImplicitStimulusProcess is next build. The broken sendMessage/getRecipients/
getWorld code in General.hs is deleted and replaced with the working stub.

### 6. RESOLVED — error is inside the RhineM abstraction, not in signal functions

The throwMaybeM convention applies to GameComputation (which has MonadError via ExceptT).
RhineM has no ExceptT — no MonadError to throw into. The `error` in lookGameState is an
implementation detail of the newtype, invisible to signal functions (they call lookGameState
and get GameState). The Nothing case is provably unreachable after gameLoop seeds
`Last (Just gs)`. Same category as the existing lobby `error` in processOneJoin.

### 7. RESOLVED — processLeavesSF replaced with new implementation

New processLeavesSF added to plan using RhineM interface (lookGameState/addGameState).
Removes departed agents from sceneAgents, announces departures to remaining
Denizens via NarrationMap. Runs before joins in the pipeline:
deliverNarrationSF >-> processLeavesSF >-> processJoinsSF >-> ...

SUPERSEDED DETAIL: the first rewrite detected departure via `agentKind == Denizen`
plus absence from acPlayerMap. That conflates "Denizen" with "player" — #2 established
Denizen = characters INCLUDING NPCs, so any future NPC Denizen would be flagged departed
every tick, ripped from its scene, with a departure announcement. Predicate replaced
with session-based detection: gid ∈ acKnownPlayers values AND gid ∉ acPlayerMap values.
acKnownPlayers already exists in AppCtx (read in processOneJoin) — no new state.
AgentKind plays no role in detection.

### 8. RESOLVED — joiner excluded from arrival narration

Joiner gets "Welcome, X!" (new) or "Welcome back!" (returning) from executeJoin.
"X has arrived." goes to other Denizens in the scene only. recipientGids now excludes
the joining player's GID in both branches.

### 9. RESOLVED — structured Narration sent to client

GameNarration changed from `[RichText]` to `Narration` (WireProtocol.hs). deliverNarrationSF
sends `GameNarration narr` — the four fields arrive as distinct arrays of RichText spans.
TypeScript client receives structured data and handles rendering. Narration gains
FromJSON/ToJSON + derivingTypeScriptDefinition in Core.hs.

### 10. RESOLVED — Either JoinError JoinResult prevents ghost sessions

processOneJoin returns `Either JoinError JoinResult`. Missing agent or scene returns
`Left (JoinError sid "returning player agent not found")`. executeJoinsSF handles both
cases: Left sends SystemMessage to player (no session mapping), Right processes the
successful join. No ghost sessions — unmapped session means processInputSF never sees it.
New-player `error` on missing lobby stays — that's unrecoverable (broken initialization).

### 11. RESOLVED — import notes corrected, execution rule established

Fixed the stale modifyMVar reference. Execution rule: read each file before editing,
verify imports against the actual file, not the plan's notes. The plan's import section
is a guide, not a spec — the actual file contents are the source of truth.

### 12. RESOLVED — SashaMudWorld.hs `_evaluation` pulled into plan scope

#3 identified the type mismatch (`_evaluation = Evaluator eval` vs
`Map (GID Agent) Evaluator`, Core.hs) and punted it as "outside this plan's scope" —
leaving the compile blocker owned by no document. Executing the plan perfectly would
still fail the build on that line. Now File 6 of the plan: `_evaluation = mempty`
(no players at startup; processOneJoin registers evaluators per-player). Executing
the plan produces a compiling tree.
