# SashaMud Project Memory

## CRITICAL RULES (re-read before every file write/edit)
- Precedence when rules collide: user instruction > plan/critique resolutions > MEMORY.md > CLAUDE.md — rules constrain Claude's initiative, never the user
- Workflow: Claude writes, user builds, user either approves or sends the compiler errors as the next prompt
- The sashamud repo has authority — old code is single-player reference; multiplayer forces fundamental changes; sashamud plans/MEMORY/code win on divergence
- NEVER invent constructor names, type names, or patterns not in old code
- Old code constructor: `ImplicitStimulusVerb ImplicitStimulusVerb` in StimulusVerbPhrase — use it exactly
- When tempted to "improve" a name from old code, STOP and ASK instead
- NEVER run builds or tests unless user explicitly requests it
- When user asks for a commit message, give them the message text — do not run git commit
- Effects CONTRIBUTE to building GameState — never say "modify", "delta", or "read-only"
- Do not invent bridging mechanisms between old and new code — when there's a gap, ASK
- DSL GADT constructors are small composable pieces from old code — do not invent monolithic constructors
- Do not add complication the user didn't ask for
- NEVER use the auto memory directory with `-` prefix — use /home/mlitchard/gitlab/sashamud/.claude-memory/ instead
- Write what things ARE. No contrastive framing ("not X", "NOT the Y"). State the positive. The negative is noise that carries confusion forward.
- NEVER invent file names, module names, or function names — find them in old code or ASK
- NEVER invent helper functions — if old code doesn't have it, you don't need it
- The evaluator is PURE DISPATCH — pattern match and delegate. Lookup logic belongs elsewhere (old code: ActionDiscovery, ActionManagement)
- Study old code THOROUGHLY before writing. Read the actual files. Do not summarize from memory and fill gaps with guesses.

## Rhine Architecture (verified from source + koans)
- Rhine source: /home/mlitchard/github/rhine
- Rhine koans: /home/mlitchard/github/rhine-koans
- MonadSchedule is in Data.Automaton.Schedule, NOT Control.Monad.Schedule.Class
- StateT CANNOT be used with |@| — Rhine koans say this explicitly (koan 3/3)
- AccumT is Rhine's answer for shared state across multiple clocks
- Millisecond n has Clock IO only — need ioClock waitClock to lift
- flow returns m void — never returns, infinite loop via reactimate
- IO MonadSchedule uses forkIO internally (true concurrency)
- GameState is OUTPUT — built each tick from accumulated behaviors via constructor (IX pattern)
- Effects CONTRIBUTE to building GameState — they don't modify anything
- GameComputation is the context in which effects contribute their pieces to the GameState under construction
- GameState lives directly in AccumT — no WorldAccum intermediary
- IX reference: `eGameState = GameState <$> bAgentMap <*> bPlanetMap <@ eTick` then `reactimate`
- Signal functions: processLeavesSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF >-> deliverNarrationSF (one sequential PlayerTick branch — narration delivered at end of tick)
- processInputSF bridge: lexify tokens → parseTokens → eval → unwrap GameComputation (StateT/ExceptT/ReaderT/Identity) → add gs'
- No TVar for GameState — lives in AccumT
- No naked domain identifiers — newtypes (SessionId, PlayerNameVAL). GameCommand carries raw Text on purpose: unparsed input, consumed at exactly one site (processInputSF → lexify). The typed command is Sentence — typing happens by parsing, not by wrapping
- AppM is a newtype over ReaderT AppCtx Handler (like Quux)
- Server.Session removed — acSessions phase map (SessionPhase sum type in Server.App) holds session lifecycle
- deliverOutbound thread outside network reads acOutbound, routes via acSessions sessionSend
- PlayerJoined fires at websocket attach (AwaitingSocket → AwaitingJoin promotion in gameWebSocket) — network decides new vs returning player
- GID assignment: counter in AppCtx IORef (acNextAgentId :: IORef PInt), atomicModifyIORef' + succPInt in processOneJoin; PInt is a bare newtype, hidden constructor, only succPInt/unPInt/firstPlayerId exported — no subtraction by construction
- Rhine tutorial: /home/mlitchard/github/rhine-tutorial

## IX EventNetwork Pattern — GameState Construction
- GameState is reconstructed each tick from current GameState + player input
- IX pattern: `updateAMap :: DAgentMap -> AgentMap -> AgentMap` — current state + change description → new state
- `eGameState = GameState <$> bAgentMap <*> bPlanetMap <@ eTick` — construction from behaviors
- Effects inhabit GameState via dispatch tables (ActionManagementFunctions) on entities (scenes, agents). The game world carries the effect configuration.
- Effect functions (ActionEffectKeyF) live in PossibilityGraph (ComputationContext). Dispatch tables live on entities in GameState.
- Evaluator is the parser/dispatcher: text → scene dispatch table → GID → PossibilityGraph → effect function.
- Current GameState is input to next tick. Registries and dispatch tables carry forward. Narration is ephemeral — extracted, delivered, cleared.
- Old code reference: sasha-engine/src/TopLevel.hs runGameWithInput (lines 123-149)
- IX reference: /home/mlitchard/github/ix/src/IX/Reactive/EventNetwork.hs

## Package Structure
- sasha-grammar: language foundation (parser, lexer, verb/noun types)
- sasha-vocabulary: swappable word lists
- sasha: THE APPLICATION — engine, API, server, model types, DSL, Rhine
- sashamud-world: game content ONLY (scenes, agents, world definition) — pure library
- sashamud-server: thin top-level package — sasha-server executable (wires server + game content)
- Server CODE (Server.hs etc) is in sasha
- Dependency: sasha-grammar <- sasha-vocabulary <- sasha <- sashamud-world <- sashamud-server
- Future e2e tests go in sashamud-server

## Nix/Flake
- shelpers from gitlab:platonic/shelpers for dev commands
- start-sashamud shelper: starts caddy + server
- client-check: runs sasha-client-generator, type-checks output with tsc
- sasha-server nix package references legacyPackages.sashamud-server
- needs meta.mainProgram for nix run to find the right binary
- Clay removed from project — TextColor enum instead
- Generated client.ts goes to web/packages/type-gen-output/src/client.ts

## Consolidation Decisions (intentional, not gaps)
- Model/Core/ consolidated: GameState, Agent, Scene, World, EntityKey, Defaults all in Core.hs
  - Mappings.hs eliminated — everything in Core.hs
- Engine/Simulation/ consolidated: RhineM, signal functions, routing all in SignalNetwork.hs
  - Clocks.hs stays separate
- Session.hs removed: acSessions MVar (Map SessionId SessionPhase) replaces GameSessionRegistry — acConnections and acPlayerMap consolidated into it (SessionPhase in Server.App: AwaitingSocket PlayerNameVAL | AwaitingJoin PlayerNameVAL sendFn | InGame sendFn (GID Agent); projections sessionGid/sessionSend)
  - Authentication.hs handles auth pipeline instead
- SessionId lives in Model.Core (breaks circular import with WireProtocol)
- WireMessage.SessionId renamed to SessionAck (avoids name collision with SessionId type)

## Current State
- WebSocket message refactor DONE
- Ping/Pong through Rhine network — proves full pipeline works
- build-0 DONE: minimal dev env as root commit (branch: build-0-orphan)
- build-1 DONE: all existing code rebased on build-0 (branch: main, build-1)
- formatter = pkgs.nixpkgs-fmt + nix-formatting check added to flake.nix and .gitlab-ci.yml
- Commit 2 DONE and merged to main (2026-07-11): look end-to-end + witness system, green build, user verified two-client runtime. 2-look merged origin/main (flake.nix union-resolved, flake.lock regenerated), then to main. Deployed via deploys repo (nix flake update sasha, nix run .#arges — nixinate to arges host)
- Implementation plan at /home/mlitchard/.claude/plans/replicated-dreaming-shell.md
- No standalone `runComputation` function — IX pattern: state lives in reactive framework (AccumT), computation runs within it. Rhine integration (Step 4) handles this in processInputSF.
- Removed as muddled (2026-07-11): .claude-memory/next-session-prompt.md (stale Step 2b trap — remove-worldaccum-prompt.md is the handoff), docs/memory/MEMORY.md (June copy — this file is the only memory), and SYNTHESIS.md (fleet review from another machine — actionable items executed, path claims wrong here)

## Step 3c State
- Core.hs changes DONE: Evaluator newtype added (`GID Agent -> Sentence -> GameComputation Identity ()`), `_evaluation :: Evaluator` on GameState, ActionEffectKeyF changed to `GID Agent -> ActionEffectKey -> GameComputation Identity ()`, makeLenses added
- General.hs DONE: pure dispatch (eval → evalImperative → evalStimulusVerbPhrase → manageImplicitStimulusProcess), imports from Engine.ActionDiscovery.Percieve.Look
- ActionProtocol refactor DONE (user-approved plan /home/mlitchard/.claude/plans/purrfect-painting-mochi.md):
  - Engine/ActionDiscovery/Protocol.hs — ActionProtocol class, actor GID explicit (`runActionProtocol :: GID Agent -> ActionInput actionF -> ...`), fetchAction/fetchAgentAction/fetchSceneAction use throwMaybeM (Text errors, no `error`), agent/scene lookups inlined (fetchPlayerAction gone; scene resolved via agentLocationMap lookup — agentCurrentScene removed)
  - Engine/ActionDiscovery/Instances.hs — single ImplicitStimulusF instance, veto chain calls pass actorGid (`ps actorGid playerKey`)
  - Engine/ActionDiscovery/Percieve/Look.hs — manageImplicitStimulusProcess (keeps old "Percieve" spelling)
  - lookupImplicitStimulus added to Engine/Resolution/ActionManagement.hs (analog of old GameState/ActionManagement.hs)
  - sasha.cabal: 4 modules added to both library exposed-modules and sasha-tests other-modules (incl. Engine.Evaluators.Player.General)
- NO ctxActingAgent — actor GID passed explicitly at every level
- Evaluator takes Sentence (not Text) — lex/parse belongs in Rhine pipeline (Step 4)
- NO defaultEvaluator wrapper — evaluator IS eval directly

## Remaining for Step 3c to compile
- SashaMudWorld.hs: `_evaluation = Evaluator eval` is a type mismatch vs `Map (GID Agent) Evaluator` — fix owned by remove-worldaccum plan File 6 (`mempty`)
- Cascading: Builder.hs may need updates if GameState construction breaks
- Not yet compiled — user runs builds

## Witness System Design (rebuilt 2026-07-11, user-ruled, supersedes the stripped design)
- Shape: capability lives ON THE WITNESS AGENT — each Denizen carries `WitnessManagementKey (GID WitnessF)` in its own ActionManagementFunctions. Witnesses perceive; the actor pushes nothing. Concealment later = GID swap — state IS which GIDs are mapped.
- Registration: `WorldOutcome` gained constructor `WitnessEffect NarrationComputation`, registered in WorldOutcomeRegistry via existing `linkWorldOutcomeEffect` on the same key as the actor narration (sceneLookGID key — playerKey pass no-ops, so witnesses fire exactly once)
- NarrationComputation is the semantic "what happened" datum: actor-side renders LookNarration as "You look around." (youSeeM); witness-side renders the same datum as "{actor} looks around." (witnessLookM, targets _actionConsequence)
- Machinery mirrors ImplicitStimulusF: WitnessEffectF (witness→actor→datum), `WitnessF` (ONE constructor now; blocked variant arrives with stealth, commits 10/11), WitnessMap inside ActionMaps, `witnessF = WitnessF processWitnessEffects` in ConstraintRefinement.Actions, `lookupWitness` in ActionManagement.hs
- Discovery walk in processWitnesses: agentLocationMap → sceneMap → sceneAgents minus actor, Denizen filter — every lookup miss is a silent no-op
- DSL: DeclareWitnessGID / CreateWitnessManagement (mirrors of the ISA pair); Builder has bsNextWitnessGID counter; attachment reuses playerBehavior; WitnessMap travels inside ActionMaps into PossibilityGraph
- Plan: /home/mlitchard/.claude/plans/snazzy-whistling-pancake.md — engine test for witness narration (feature-ordering.md:45) deferred, add on user instruction

## NarrationMap Design
- NarrationMap = Map (GID Agent) Narration — per-player routing
- Routing (who sees what) is NarrationMap's concern. Content structure (playerAction/consequence/epilogue) is Narration's concern. Orthogonal.
- GameState holds NarrationMap
- Narration fields: _playerAction (actor's action "You look around."), _actionConsequence (scene description), _presenceListing ("Also here: ..."), _actionEpilogue
- Rendering order: playerAction → actionConsequence → presenceListing → actionEpilogue

## Design Decisions
- Actor GID passed explicitly: pipeline → evaluator → effects
- ComputationContext holds only _ctxPossibilityGraph (witness system stripped 2026-07-11)
- agentCurrentScene REMOVED (single-player vestige). Where-is-agent authority: `_agentLocationMap :: Map (GID Agent) (GID Scene)` on GameState. Departure leaves entry intact — returning players land where they were; `ReturningLocationMissing` JoinFailure if absent
- defaultActionManagement — use ActionManagementFunctions mempty directly
- defaultPossibilityGraph — builder constructs its own
- defaultGameState is local to SashaMudWorld
- Old code defaults in sasha-core/src/Model/Core/Defaults.hs: defaultScene, defaultWorld, defaultNarration, defaultAgent, defaultObject, defaultBatch
- PerceptionMap and SpatialRelationshipMap removed from World — needed for future verbs
- WorldAccum removal plan APPLIED (2026-07-11, all 6 files) — see /home/mlitchard/gitlab/sashamud/.claude-plans/remove-worldaccum.md. Not yet compiled — user builds. Import deviation from plan (critique #11 verification): Narration/ComputationContext record construction needs field names imported (`_playerAction` etc., `_ctxPossibilityGraph`) — plan listed only constructors; fields added to imports in SignalNetwork.hs and General.hs
- Adversarial critique of that plan (numbered, addressing one at a time): /home/mlitchard/gitlab/sashamud/.claude-plans/remove-worldaccum-critique.md — #1 WITHDRAWN (Narration derives Semigroup/Monoid via Generically, Core.hs:218 — lawful; Semigroup for unionWith merge, Monoid for `non mempty` in modifyAgentNarration Perception.hs:39). #2 RESOLVED: AgentKind is Denizen|Fixture (Denizen = characters incl. players, Fixture = object-agents — old SashaLambdaDSL.hs:710, old Server.hs:218); PlayerAgent was invented, renamed to Denizen everywhere. #3 RESOLVED: processInputSF looks up evaluator per agent, processOneJoin registers Evaluator eval; SashaMudWorld.hs:67 type mismatch (should be mempty) is pre-existing Step 3c issue. #4 RESOLVED: no stale-read — IO MonadSchedule interleaves via MVar (one worker per step), heartbeat contributes Last Nothing, all writers sequential on one PlayerTick chain. #5 RESOLVED: stub is user-approved, no-stubs rule applies to Claude only; this build verifies pipeline, real dispatch is next build. #6 RESOLVED: error inside RhineM newtype, no MonadError in stack. #7 RESOLVED: processLeavesSF rewritten with RhineM interface. #8 RESOLVED: joiner excluded from arrival narration. #9 RESOLVED: GameNarration carries Narration (not [RichText]). #10 RESOLVED: Either JoinError JoinResult prevents ghost sessions. #11 RESOLVED: verify imports against actual file during execution. #12 RESOLVED: SashaMudWorld.hs `_evaluation = mempty` pulled into plan scope as File 6 (was orphaned between #3 and Step 3c). #7 SUPERSEDED DETAIL: departure detection is session-based (gid ∈ acKnownPlayers ∧ gid ∉ acPlayerMap) — the first rewrite used agentKind == Denizen, which would flag NPC Denizens departed every tick. All critiques resolved IN THE PLAN; the plan is now APPLIED in code.
- RhineM is a newtype over `AccumT (Last GameState) (ReaderT PossibilityGraph (ReaderT AppCtx IO))`
- RhineM hides Last/Maybe — signal functions use lookGameState/addGameState/askAppCtx/askPossibilityGraph
- MonadSchedule for RhineM: from monad-schedule package (`Control.Monad.Schedule.Class`), NOT `Data.Automaton.Schedule` — that module is automaton 1.8 API, installed set has automaton 1.6.1. Instance follows monad-schedule's IdentityT passthrough (`fmap unRhineM >>> schedule >>> fmap (fmap (fmap RhineM)) >>> RhineM`); no hoistS. `monad-schedule` in sasha.cabal build-depends (library + tests). Local ~/github/rhine checkout is AHEAD of installed versions — check installed version before copying its API
- AccumT accumulates `Last GameState` (Data.Monoid.Last wraps Maybe) — lawful Monoid
- `Last Nothing` = no contribution (lift/liftIO), `Last (Just x) <> Last (Just y) = Last (Just y)` — newer wins
- GameState has NO Semigroup/Monoid — Last provides it for AccumT
- Pure replacement Semigroup on GameState fails right identity (`x <> mempty = mempty ≠ x`) — breaks AccumT (look after liftIO returns mempty)
- Narration accumulates within a tick via StateT, deliverNarrationSF delivers at end of the same tick, then flushes
- All state-modifying SFs sequential on one PlayerTick (parallel clock safety)
- GID counter lives in AppCtx IORef (acNextAgentId :: IORef PInt), not in the accumulator — single-thread access, atomicModifyIORef'
- processLeavesSF rewritten using RhineM interface — detects departed players session-based (gid ∈ acKnownPlayers ∧ gid has no InGame session in acSessions), removes from scenes, announces via NarrationMap
- Departure detection NEVER uses AgentKind — Denizen includes NPCs; acKnownPlayers is the "is a player" source of truth
- Game state vs server state: GameState (AccumT, single writer = PlayerTick chain) holds world truth; AppCtx (MVars/TChans, multi-writer) holds session/socket truth — disconnects are async, never route through the chain
- One authority per question: is-a-player = acKnownPlayers, is-connected = acSessions InGame phase, is-in-scene = sceneAgents, character-or-object = AgentKind — never proxy one for another
- Persistence debt: acKnownPlayers (name→GID) and acNextAgentId (PInt GID counter) are world truth living in AppCtx — when save/load lands, they must be persisted alongside GameState, or a restart loses player identities and reissues colliding GIDs
- AnalysisViewport = Parser | State | Meta | Graphics | GameMap — sum type keys AnalysisData (was Map Text; raw Text key silently dropped on client, ViewportManager.ts:65). In remove-worldaccum plan File 2. No producer yet; client key mapping updates when telemetry lands
- Player input growth path (user-approved design): `data PlayerInput = UnVerifiedInput PUVI | VerifiedInput PVI` — PUVI/PVI are newtypes over Text. Wire Text wraps to PUVI at receipt; lexify accepts PVI only — unverified input cannot reach the parser by construction. First verifier is a pass-through (user-sanctioned placeholder); real checks (length cap, rate limit, character policy) replace it later
- Errors in the signal chain are sum types, rendered to Text only at the display boundary: JoinFailure (ReturningAgentMissing | ReturningSceneMissing) inside JoinError, joinFailureText at executeJoinsSF → SystemMessage. Never naked Text in an Either
- Future cut (user-approved): lexify/parseTokens return Either Text — sasha-grammar gets error sum types + render functions, same principle as JoinFailure
- Future cut (user-approved): GameComputation ExceptT Text becomes ExceptT GameError (sum type + renderer) — Core surgery touching every evaluator/effect, own commit
- MVar reads (supersedes the snapshot-threading ruling, which belonged to the deliver-first ordering): with deliverNarrationSF at the end of the chain, each SF reads the MVars it needs directly — processLeavesSF reads acSessions + acKnownPlayers; processJoinsSF reads acKnownPlayers; processInputSF reads acSessions post-join (executeJoinsSF promotes AwaitingJoin → InGame mid-tick, new player's first command routes same-tick); deliverNarrationSF reads acSessions at tick end; heartbeatSF reads acSessions. SFs project gids via sessionGid. Dead-session sends are safe: deliverOutbound logs SendDropped
- NarrationMap Semigroup uses `unionWith (<>)` to merge per-player narrations
- Narration ordering is CHRONOLOGICAL within a field: always append new entries (`<> [x]`, `flip (unionWith (<>)) newMap`) — never cons/prepend; user-ruled 2026-07-13 (raj arrived/looks-around backward bug)
- "Not in IO" principle (user-ruled 2026-07-13): IO phases gather inputs and deliver outputs — TRANSPORT ONLY. Every game decision (incl. error judgment/rendering, who gets told what) lives in the GameComputation and throws/narrates there. Never respond to game events from the IO gather phase — that's a second authority outside the composed computation
- NEVER swallow errors in the signal pipeline (user-ruled 2026-07-13): failed lookups inside the composed computation throwError at the point of failure — no silent `Nothing -> pure ()` branches. ExceptT short-circuits; error evaluated after execution like every other throw
- Generator pattern (user-ruled 2026-07-13): pure per-tick functions return `(dataForIOPhase, GameComputation Identity ())` — processJoinsPure `([JoinResult], comp)`, resolveCommands `([SessionId] pings, comp)`. Composition of per-item computations happens IN the generator (mapM_), not in the caller. Classify messages exactly once (partition by pattern-match comprehension) — no dead branches re-dissecting them downstream. Generators run at the generation site (playerTickBlock let); the sequencer (composeTick) takes only computations and generation-time data — never raw maps to re-generate from. Data that doesn't depend on GameState never routes through the executed computation's return value (adversarial-cleanup plan, applied 2026-07-13)
- Login race FIXED (2026-07-12, branch 4-login-bug-fix, plan .claude-plans/session-phase.md, executed in 4 gated steps): loginHandler inserts AwaitingSocket at HTTP login (evicting stale same-name AwaitingSocket entries); PlayerJoined fires at websocket attach — a join cannot exist before its send function does, by construction. executeJoin promotes AwaitingJoin → InGame atomically. The race-codifying tests ("login creates agent in agentMap", "multi-player: both in lobby") were rewritten to connect and prove the join via auto-look narration; reproducer test "auto-look survives a slow websocket connect" (login, 3s delay, connect, expect auto-look) guards the regression. Accepted residual leak: a name that logs in and never connects leaves one AwaitingSocket entry, self-healed on next same-name login — noted beside the persistence debt
- Types with commit-2-only constructors gain more constructors in future commits
- TH staging: all makeLenses and derivingTypeScriptDefinition calls at bottom of Core.hs, single TH stage

## Code Rules (learned the hard way)
- ALL packages use NoImplicitPrelude — always include it in default-extensions
- NEVER qualify imports — use explicit imports only, stop and ask on name collisions
- When qualified import is needed, qualifier is the module name — no aliases
- NEVER second-guess user instructions — apply them, come back with compiler error if it fails
- ALWAYS use lenses (view, set, over), NEVER direct record field access
- Never use _fieldName accessors — use the lens equivalent without underscore
- Import from Lens.Micro.Platform (view, set, over) as needed
- NO partial pattern matches — use case with all branches handled
- NO head, NO [x] = expr, NO incomplete patterns
- ALWAYS check old code FIRST before writing ANY pattern
- If pattern not in old code, STOP and ASK — do not guess at APIs or function names
- Do not pre-debate whether something will compile — make the change, let the compiler decide
- Use Map.lookup with a specific key, not elems/toList dumping
- ONLY do what is asked — do not show initiative, do not make extra changes
- Do not invent names — use old code naming conventions (TopLevel, ActionManagement, etc.)
- Do not touch files the user did not ask you to touch
- When editing a file, do NOT reformat surrounding content — preserve the user's formatting exactly
- Use minimal, targeted Edit calls — only change what was asked, leave everything else untouched
- NEVER write stubs, placeholders, or fake implementations — if a field requires a stub value, the field should not exist yet
- If a type/field has no real implementation yet, do not add it to the data type. Add it when the real code arrives.
- DerivingVia needs the constructor in scope: import Foo (Foo) not just the type
- Use Data.Time.Calendar for Year (= Integer), MonthOfYear (= Int), Day, toGregorian — NEVER roll custom date types
- Check Hackage BEFORE inventing any type — if the standard library has it, use it
- ALL tests use hspec-discover — Main.hs is just `{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`, never manual spec wiring
- NEVER run builds or tests unless user explicitly requests
- When user asks for commit message, give the TEXT — do not run git commit
- GameState is CONSTRUCTED from accumulated pieces. Builder accumulates, then constructs.
- Before deleting files, confirm with user — destructive operation
- Test types with real structure. Trivial newtypes over primitives (GID over Int) prove nothing.

## Testing Pattern (from quux/server)
- JSON roundtrip with QuickCheck: `checkJSON = property $ \(a :: a) -> Just a == decode (encode a)`
- One JSONSpec.hs with `prop` lines for each JSON type
- Arbitrary instances via `#ifdef TESTING` in source modules — imports at top, deriving at bottom
- Test exe uses `hs-source-dirs: test src` + `cpp-options: -DTESTING` to recompile source with flag
- `CPP` in default-extensions, `generic-arbitrary` + `QuickCheck` + `quickcheck-instances` + `hspec-core` in build-depends
- `Test.Hspec.QuickCheck (prop)` comes from `hspec-core` — quux uses `hspec-core`
- GenericArbitrary for sum/product types, `deriving newtype` for newtypes
- Large enums (many constructors): derive `Bounded, Enum`, use manual `instance Arbitrary Foo where arbitrary = arbitraryBoundedEnum` — GenericArbitrary chokes on the constraint solver (quux FFTSize pattern)
- Complex sum types with GenericArbitrary need `{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}` at top of module (quux pattern: Messages.hs, WebSocket.hs, Authorization.hs)
- ALWAYS study quux/old code BEFORE writing Arbitrary instances — do not guess the pattern

## Key Files
- Architecture doc: /home/mlitchard/gitlab/sashamud/docs/monorepo-redesign.md
- Commit-1 doc: /home/mlitchard/gitlab/sashamud/docs/roadmap/commit-01-working-mud.md
- Feature ordering: /home/mlitchard/gitlab/sashamud/docs/roadmap/feature-ordering.md
- Old code: /home/mlitchard/gitlab/sasha/ (patterns, not gospel)
- Rhine source: /home/mlitchard/github/rhine
- Rhine koans: /home/mlitchard/github/rhine-koans
- Quux server (DB patterns): /home/mlitchard/gitlab/quux/server
- Memory: /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md (NOT the auto directory with - prefix)
