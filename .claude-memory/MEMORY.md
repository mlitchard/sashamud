# SashaMud Project Memory

## CRITICAL RULES (re-read before every file write/edit)
- NEVER invent constructor names, type names, or patterns not in old code
- Old code constructor: `ImplicitStimulusVerb ImplicitStimulusVerb` in StimulusVerbPhrase — use it exactly
- When tempted to "improve" a name from old code, STOP and ASK instead
- Effects CONTRIBUTE to building GameState — never say "modify", "delta", or "read-only"
- Do not invent bridging mechanisms between old and new code — when there's a gap, ASK
- DSL GADT constructors are small composable pieces from old code — do not invent monolithic constructors
- Do not add complication the user didn't ask for
- Write what things ARE. No contrastive framing ("not X", "NOT the Y"). State the positive. The negative is noise that carries confusion forward.
- NEVER invent file names, module names, or function names — find them in old code or ASK
- The evaluator is PURE DISPATCH — pattern match and delegate. Lookup logic belongs elsewhere (old code: ActionDiscovery, ActionManagement)
- Study old code THOROUGHLY before writing. Read the actual files. Do not summarize from memory and fill gaps with guesses.
- Agent cost (user-ruled 2026-10-13): verbatim lookups in old code or reference checkouts go to the quote-source agent, or a general agent with `model: haiku`. One directory and the exact names to find. Only for text not already in context. Haskell is written by a general-purpose agent with `model: opus` from a spec the default model produces (file, old-code quote, names, shape); the default model reads the diff once. Hooks in .claude/settings.json enforce both. The CLAUDE.md persona leaks into agent reports; the prompt says to return quoted text only.
- Old code is the source to build from (user-ruled 2026-10-13, refined 2026-10-16). It is broken in places, so a pattern taken from it is checked against sashamud's rulings and code before it is applied, and a broken part is raised with him. When old code or an existing sashamud convention settles a name, a shape, or a path, apply it. Follow the old main path only. Ask only where sashamud has no pattern and old code has none.
- Scope is what was asked. World content, tests the user did not order, and docs reads the user did not order are out. "Mechanism" work means grammar, core types, DSL constructors, builder, engine; wiring a world object through the DSL is the author's job.
- The old-code lookup rule covers Haskell shapes in grammar, core, DSL, builder and engine. It does not cover JavaScript in the e2e harness, cabal lines, nix, or a fix whose shape is already in context. Before any lookup, name the decision it would change. No decision, no lookup (user-corrected 2026-10-13).
- Changes land on the current branch only, ever. Never switch branches, never touch main (user-ruled 2026-10-13).
- Infrastructure ships as code; the DSL applies it (user-ruled 2026-10-15). Infrastructure is grammar, vocabulary, lexer, core types, DSL constructors, builder and engine. It is delivered as normal code in the codebase and reaches the live server through a server release. Applying infrastructure to the world happens in .dsl files delivered with deploy-dsl. Example: the RED adjective ships in sasha-grammar; a .dsl file puts it to use.
- No naked products, ever (user-ruled 2026-10-21): a function that returns several values returns a record with named fields.

## Rhine Architecture (verified from source + koans)
- Rhine source: /home/mlitchard/github/rhine
- Rhine koans: /home/mlitchard/github/rhine-koans
- Rhine tutorial: /home/mlitchard/github/rhine-tutorial
- MonadSchedule is in Data.Automaton.Schedule, NOT Control.Monad.Schedule.Class
- StateT CANNOT be used with |@| — Rhine koans say this explicitly (koan 3/3)
- AccumT is Rhine's answer for shared state across multiple clocks
- AccumT carries state ACROSS ticks. StateT runs WITHIN a tick (GameComputation uses StateT for effect execution inside a single tick). Two layers, two jobs.
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
- No naked domain identifiers — newtypes (SessionId, PlayerNameVAL). GameCommand carries raw Text on purpose: unparsed input, consumed at exactly one site (processInputSF → lexify). The typed command is Sentence — typing happens by parsing, not by wrapping
- AppM is a newtype over ReaderT AppCtx Handler (like Quux)
- Server.Session removed — acSessions phase map (SessionPhase sum type in Server.App) holds session lifecycle
- deliverOutbound thread outside network reads acOutbound, routes via acSessions sessionSend
- PlayerJoined fires at websocket attach (AwaitingSocket → AwaitingJoin promotion in gameWebSocket) — network decides new vs returning player
- GID counters: PInt is a bare newtype with a hidden constructor; only succPInt/unPInt/firstGID are exported, so counters only go up. BuilderCounters (one PInt per GID kind) seeds from firstGID, lives in AppCtx as acBuilderCounters, and the signal network reads it before a live DSL run and writes the result back. firstGID was renamed from firstPlayerId on 2026-10-13; the player-counter use it was named for is gone

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
- Server CODE (Server.hs etc) is in sasha
- Dependency: sasha-grammar <- sasha-vocabulary <- sasha <- sashamud-world
- Future e2e tests go in sashamud-world

## Nix/Flake
- shelpers from gitlab:platonic/shelpers for dev commands
- start-sashamud shelper: brings the lpg database up, exports SASHA_DB_CONNSTR, then starts caddy + server
- Local authentik VM (nixosConfigurations.authentik-local): secrets for it live as let bindings in flake.nix, by user ruling 2026-10-01. The VM is local only, so this is the one place a secret may sit in the repo. Its login page comes from authentik/flow-default-authentication-flow.yaml, swapped into the shipped blueprints directory after the authentik-nix override-scope test pattern.
- client-check: runs sasha-client-generator, type-checks output with tsc
- sasha-server nix package references legacyPackages.sashamud-server
- needs meta.mainProgram for nix run to find the right binary
- Clay removed from project — TextColor enum instead
- Generated client.ts goes to web/packages/type-gen-output/src/client.ts

## STM Channel Usage
- TChan for server-lifetime channels (acInbound, acOutbound, acJoinChan) — unbounded STM FIFO, no locks, multiple writers safe via STM optimistic concurrency
- TMChan for per-player/per-session channels — closeable, `closeTMChan` on disconnect signals readers with `Nothing`, resources reclaimed by GC after close

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
- Shape: capability lives ON THE WITNESS AGENT — each Denizen carries `_agentWitnessManagement :: Map VerbKey (GID WitnessF)`. Witnesses perceive; the actor pushes nothing. Concealment later = GID swap — state IS which GIDs are mapped.
- NarrationComputation is actor-side only now: LookNarration renders as "You look around." (youSeeM) via NarrationEffect in the WorldOutcomeRegistry. Witness-side rendering lives in the WitnessF itself (witnessLookM, "{actor} looks around.", targets _actionConsequence)
- Machinery mirrors ImplicitStimulusF: WitnessEffectF (witness→actor, self-contained, no datum), `WitnessF` (ONE constructor now; blocked variant arrives with stealth, commits 10/11), `_witnessMap` registry in PossibilityGraph, `witnessF = WitnessF processWitnessEffects` in ConstraintRefinement.Actions
- Discovery (user-ruled 2026-07-13): sceneAgents minus actor ARE the witnesses — no AgentKind filter, no agentMap-based candidate filtering. Per-witness effect SELECTION is dispatch through the witness's own data (mirrors the veto system), currently WitnessManagementKey → witnessMap; lookup misses stay silent no-ops
- Witness redesign APPLIED 2026-07-13 (all rulings in, not yet compiled — user builds): mirrors veto system exactly. VerbKey lives in sasha-grammar Grammar.Parser.GCase, sole constructor ImplicitStimulusKey ImplicitStimulusVerb (user-named; old GCase.hs deriving shape). Agent field `_agentWitnessManagement :: Map VerbKey (GID WitnessF)` (user-named). WitnessEffectF dropped the NarrationComputation datum (user-ruled): `GID Agent -> GID Agent -> GameComputation Identity ()` — VerbKey selects the effect, so the chosen WitnessF is self-contained (processWitnessEffects = witnessLookM). Trigger: worldOutcomeEffects witness path is OBSOLETE (user-ruled) — WitnessEffect constructor removed from WorldOutcome; NarrationEffect/youSeeM still ride the registry. runActionProtocol success branch (Instances.hs) fires `processWitnesses actorGid (ImplicitStimulusKey verb)` after ps/ls — vetoed actions notify nobody. processWitnesses: sceneAgents minus actor; throwMaybeM on location/scene and on dangling witnessMap GID (no-swallow rule); VerbKey miss in agent's map = silent no contribution (ruled). DSL: WitnessBehavior constructor / witnessBehavior wrapper (follows PlayerBehavior/SceneBehavior convention) inserts (VerbKey, GID WitnessF) into the template's map; world wires `witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID`. Old-path vestiges REMOVED on user order 2026-07-13 (after tests passed): WitnessManagementKey constructor, CreateWitnessManagement/createWitnessManagement, lookupWitness, and the world's witnessKey attachment are all deleted — ActionManagement is single-constructor (ISAManagementKey) until more verbs land. DeclareWitnessGID/witnessF/witnessMap/processWitnessEffects are LIVE (new path)
- NEVER declare existing machinery superseded/orphaned/dead by inference — new mechanisms are ADDITIVE until the user explicitly rules removal (user-corrected twice 2026-07-13)
- DSL: DeclareWitnessGID declares the function into bsWitnessMap (Builder has bsNextWitnessGID counter); attachment is WitnessBehavior/witnessBehavior writing (VerbKey, GID WitnessF) into the agent template's _agentWitnessManagement; bsWitnessMap lands in PossibilityGraph._witnessMap
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
- Departure detection NEVER uses AgentKind — Denizen includes NPCs; the users table is the "is a player" source of truth
- Persistence debt: acKnownPlayers (name→GID) and acNextAgentId (PInt GID counter) are world truth living in AppCtx — when save/load lands, they must be persisted alongside GameState, or a restart loses player identities and reissues colliding GIDs
- AnalysisViewport = Parser | State | Meta | Graphics | GameMap — sum type keys AnalysisData (was Map Text; raw Text key silently dropped on client, ViewportManager.ts:65). In remove-worldaccum plan File 2. No producer yet; client key mapping updates when telemetry lands
- Player input growth path (user-approved design): `data PlayerInput = UnVerifiedInput PUVI | VerifiedInput PVI` — PUVI/PVI are newtypes over Text. Wire Text wraps to PUVI at receipt; lexify accepts PVI only — unverified input cannot reach the parser by construction. First verifier is a pass-through (user-sanctioned placeholder); real checks (length cap, rate limit, character policy) replace it later
- Errors in the signal chain are sum types, rendered to Text only at the display boundary: JoinFailure (ReturningAgentMissing | ReturningSceneMissing) inside JoinError, joinFailureText at executeJoinsSF → SystemMessage. Never naked Text in an Either
- Future cut (user-approved): lexify/parseTokens return Either Text — sasha-grammar gets error sum types + render functions, same principle as JoinFailure
- Future cut (user-approved): GameComputation ExceptT Text becomes ExceptT GameError (sum type + renderer) — Core surgery touching every evaluator/effect, own commit
- MVar reads (supersedes the snapshot-threading ruling, which belonged to the deliver-first ordering): with deliverNarrationSF at the end of the chain, each SF reads the MVars it needs directly — processLeavesSF reads acSessions + acKnownPlayers; processJoinsSF reads acKnownPlayers; processInputSF reads acSessions post-join (executeJoinsSF promotes AwaitingJoin → InGame mid-tick, new player's first command routes same-tick); deliverNarrationSF reads acSessions at tick end; heartbeatSF reads acSessions. SFs project gids via sessionGid. Dead-session sends are safe: deliverOutbound logs SendDropped
- NarrationMap Semigroup uses `unionWith (<>)` to merge per-player narrations
- Narration ordering is CHRONOLOGICAL within a field: always append new entries (`<> [x]`, `flip (unionWith (<>)) newMap`) — never cons/prepend; user-ruled 2026-07-13 (raj arrived/looks-around backward bug). Full sweep completed 2026-07-13: bf769a5 fixed witnessLookM + merges; the five remaining cons sites (youSeeM ×3, StaticNarration actor + witness branches) converted on user instruction — no cons sites remain
- "Not in IO" principle (user-ruled 2026-07-13): IO phases gather inputs and deliver outputs — TRANSPORT ONLY. Every game decision (incl. error judgment/rendering, who gets told what) lives in the GameComputation and throws/narrates there. Never respond to game events from the IO gather phase — that's a second authority outside the composed computation
- NEVER swallow errors in the signal pipeline (user-ruled 2026-07-13): failed lookups inside the composed computation throwError at the point of failure — no silent `Nothing -> pure ()` branches. ExceptT short-circuits; error evaluated after execution like every other throw
- Generator pattern (user-ruled 2026-07-13): pure per-tick functions return `(dataForIOPhase, GameComputation Identity ())` — processJoinsPure `([JoinResult], comp)`, resolveCommands `([SessionId] pings, comp)`. Composition of per-item computations happens IN the generator (mapM_), not in the caller. Classify messages exactly once (partition by pattern-match comprehension) — no dead branches re-dissecting them downstream. Generators run at the generation site (playerTickBlock let); the sequencer (composeTick) takes only computations and generation-time data — never raw maps to re-generate from. Data that doesn't depend on GameState never routes through the executed computation's return value (adversarial-cleanup plan, applied 2026-07-13)
- Login race FIXED (2026-07-12, branch 4-login-bug-fix, plan .claude-plans/session-phase.md, executed in 4 gated steps): loginHandler inserts AwaitingSocket at HTTP login (evicting stale same-name AwaitingSocket entries); PlayerJoined fires at websocket attach — a join cannot exist before its send function does, by construction. executeJoin promotes AwaitingJoin → InGame atomically. The race-codifying tests ("login creates agent in agentMap", "multi-player: both in lobby") were rewritten to connect and prove the join via auto-look narration; reproducer test "auto-look survives a slow websocket connect" (login, 3s delay, connect, expect auto-look) guards the regression. Accepted residual leak: a name that logs in and never connects leaves one AwaitingSocket entry, self-healed on next same-name login — noted beside the persistence debt
- Types with commit-2-only constructors gain more constructors in future commits
- TH staging: all makeLenses and derivingTypeScriptDefinition calls at bottom of Core.hs, single TH stage

## Code Rules (learned the hard way)
- ALL packages use NoImplicitPrelude — always include it in default-extensions
- Every module imports SashaPrelude — it is the project's custom prelude (based on attic/core/src/SashaPrelude.hs)
- Always include type signatures
- Use Map.lookup with a specific key, not elems/toList dumping
- Do not touch files the user did not ask you to touch
- When editing a file, do NOT reformat surrounding content — preserve the user's formatting exactly
- Use minimal, targeted Edit calls — only change what was asked, leave everything else untouched
- If a type/field has no real implementation yet, do not add it to the data type. Add it when the real code arrives.
- DerivingVia needs the constructor in scope: import Foo (Foo) not just the type
- Use Data.Time.Calendar for Year (= Integer), MonthOfYear (= Int), Day, toGregorian — NEVER roll custom date types
- Check Hackage BEFORE inventing any type — if the standard library has it, use it
- ALL tests use hspec-discover — Main.hs is just `{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`, never manual spec wiring
- GameState is CONSTRUCTED from accumulated pieces. Builder accumulates, then constructs.
- Before deleting files, confirm with user — destructive operation
- Test types with real structure. Trivial newtypes over primitives (GID over Int) prove nothing.
- DSL uses free-monad-style GADT (Pure/Bind constructors give Monad instance)

## Dead Files (confirmed dead, pending removal)
- sasha/src/Error.hs
- sasha/src/Model/RandomPool.hs
- sasha/src/Server/Log.hs

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

## Conventions
- GHC2021 language
- microlens-platform for lenses
- makeLenses TH in each module
- aeson-generics-typescript fork for TS codegen (derivingTypeScriptDefinition TH splices)
- horizon-platform for Nix Haskell package set (GHC 9.6.x)
- Rhine from turion/rhine GitHub (specific commit hash)
- SessionId (Text) is the primary identifier for player sessions
- WebSocket is bidirectional: Text in (commands), WireMessage out (responses)
- AuthProtect SecWebSocketProtocol on the WebSocket route
- async package for thread management

## Key Files
- Architecture doc: /home/mlitchard/gitlab/sashamud/docs/monorepo-redesign.md
- Commit-1 doc: /home/mlitchard/gitlab/sashamud/docs/roadmap/commit-01-working-mud.md
- Feature ordering: /home/mlitchard/gitlab/sashamud/docs/roadmap/feature-ordering.md
- Old code: /home/mlitchard/gitlab/sasha/ (patterns, not gospel)
- Rhine source: /home/mlitchard/github/rhine
- Rhine koans: /home/mlitchard/github/rhine-koans
- Quux server (DB patterns): /home/mlitchard/gitlab/quux/server
- IX (reactive EventNetwork): /home/mlitchard/github/ix/
- Attic (SashaPrelude, old core types): /home/mlitchard/gitlab/sashamud/attic/
- Memory: /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md (NOT the auto directory with - prefix)

## Live DSL / Lobby (user-ruled 2026-10-14, branch 15-lobby-dsl-mechanic)
- The world is the .dsl files under sashamud-world/src. Today these are sashamud-world/src/2/Lobby/1-lobby.dsl, 2-floor.dsl and 3-ball.dsl. World-wide files go in sashamud-world/src/1/World/ and load before rooms. sashamud-world has no library stanza. It holds the .dsl files and the sashamud-world-tests executable (DSL/BuilderSpec.hs).
- sasha/src/Server/World.hs exports WorldLoadFailure(..), loadWorld, mintBootstrapToken, worldLoadFailureText, worldPrograms. worldPrograms walks SASHA_WORLD_DIR recursively. It descends with doesDirectoryExist, sorts entries, and returns the .dsl files in that order. loadWorld folds the programs from `WorldBuilderResult defaultGameState initialCounters []`.
- The server starts empty. sashamud-server/app/Main.hs is `main = startServer (WorldBuilderResult defaultGameState initialCounters [])`. The world arrives through POST /api/game/dsl from a wizard session, with the BEARER header and a JSON string body. DELETE /api/game/logout ends the session.
- Bootstrap mint is opt-in. startServer reads SASHA_BOOTSTRAP_TOKEN_FILE. When it is unset, no mint runs. SASHA_BOOTSTRAP_WIZARD names the account. The flake wrapper sets its default from the let binding bootstrapWizard ("wizard"). If a token file is set and SASHA_BOOTSTRAP_WIZARD is unset, the server exits with "bootstrap token failed: SASHA_BOOTSTRAP_WIZARD unset".
- mintBootstrapToken runs through runHandler and runReaderT over AppM. It polls for the account row once a second and prints "bootstrap account missing: <name>, waiting" once. An ambiguous match is err500 "bootstrap account ambiguous". It mints a random token and hashes it. It makes the JWT with makeJwtForTesting (secondsToNominalDiffTime 300, a five-minute token) and stores it with tryAddHashAndJwt. It inserts an AwaitingSocket session with the same hasActiveSession/keepEntry/err409 shape as authCallback. It writes the token to the path with Data.Text.IO.writeFile.
- Migrations are schema only. Account rows come from createAccount, signed with the admin sk key. In start-sashamud they come from psql, with the createAccountSql let binding and jq over the wizardAccount let binding.
- Flake let bindings: bootstrapTokenFile = "bootstrap-token", bootstrapWizard = "wizard".
- start-sashamud steps: remove the token file; start sasha-server with SASHA_BOOTSTRAP_TOKEN_FILE set; wait for the credentials table; create the wizard account with psql; wait for the token file and the port; deliver `find "$SASHA_WORLD_DIR" -name '*.dsl' | sort` with curl to POST /api/game/dsl; curl DELETE /api/game/logout; remove the token file. The teardown trap is installed after `up`, following quux (user ruling 2026-10-17).
- stop-sashamud kills the .devpids entries first, then runs pkill, then removes the token file.
- VM tests run-deploy-tests and run-end-to-end set SASHA_BOOTSTRAP_TOKEN_FILE=/root/bootstrap-token in the unit environment. They wait for the credentials table and create the wizard account with createAccount and a throwaway key. They wait for the unit, the file and the port. They deliver the world files. The deploy test then delivers study.dsl and amend-lobby.dsl. Both tests then log out.
- Test harnesses: SeleniumHarness withServer and LoginLogoutSpec withTestServer start the server empty. Before the test body runs, they log in as the wizard, post each worldPrograms file to /api/game/dsl, wait 6 seconds for the DSL tick, and log out. LoginLogoutSpec uses a temp log file through `GameLog logFileHandle (Just logFilePath)`. GameLog is `GameLog { logHandle :: Handle, logPath :: Maybe FilePath }`.
- dslTickSF (DSLTick, 5 seconds) reads `Routed sid dsl` from acDSLChan (`TChan (Routed (SashaLambdaDSL GameState))`). On Left err it logs DSLBuildFailed and sends the submitter `GameNarration` with worldBuilderErrorText in _actionConsequence. On Right next it logs `DSLBuildSucceeded [WorldChange]` and sends the submitter one plain line per change from worldChangeText. Only the submitter sees the report.
- Amendment by label: SashaLambdaDSL constructors are ModifyScene SceneLabel (Scene -> SashaLambdaDSL Scene), ModifyObject ObjectLabel (Object -> SashaLambdaDSL Object), and ModifyNewUserAgent ((Text -> Agent) -> SashaLambdaDSL (Text -> Agent)). The wrappers are modifyScene, modifyObject, modifyNewUserAgent. The names are in the DSL.Reify list. ModifyScene keeps the stored sceneAgents. Example: sashamud-server/test-e2e/amend-lobby.dsl.
- WorldBuilderError gained UndeclaredSceneLabel SceneLabel, UndeclaredObjectLabel ObjectLabel, InvalidObjectGID (GID Object) String, and MissingNewUserAgent.
- WorldChange is SceneCreated (GID Scene) | ObjectCreated (GID Object) | SceneModified SceneLabel | ObjectModified ObjectLabel | NewUserAgentModified | NewUserRegistered (GID Scene). bsChanges and resultChanges are appended in order. GID's Show instance renders the bare number, so a line reads "Scene created: 0".
- Deploys: a brief was sent to the deploys session (/home/mlitchard/gitlab/deploys, services/sashamud.nix, DynamicUser, StateDirectory sashamud). The unit needs SASHA_BOOTSTRAP_TOKEN_FILE under the state directory, the wizard account created after the schema exists, and a deliver-then-logout step.
- deploy-dsl takes `local` or `live` first, then the file. `local` uses dslServerUrl, `live` uses liveDslServerUrl (https://sashamud.net). SASHA_URL overrides either. Every caller in flake.nix passes `local`.
- Non-main deploys (user-ruled 2026-10-18): the deploys repo's sasha input names the commit, `sasha.url = "gitlab:liftlatch/sashamud/<commit hash>"`, then `nix flake update sasha` records it in flake.lock. Michael supplies the hash of the pushed branch head. A bare `gitlab:liftlatch/sashamud` follows main.

## LLM sentence repair (branch 18-llm-experiments, done 2026-10-16)
- Plan: .claude-plans/llm-sentence-repair.md, steps 1-5 done, flake check green.
- Flow: a parse failure sends that session `RepairRequest UnparsedSentence ParseFailure Gbnf [RepairAttempt]`. The client asks llama-server at localhost:VITE_SLM_PORT and answers `RepairedCommand UnparsedSentence Text SlmName`. The server allows three attempts per failure, tracked in acPendingRepairs (Server.App). A slm-absent answer ends the repair at once. The failure message goes out as SystemMessage.
- Generator: Grammar.Gbnf (sasha-grammar) holds `generateGbnf :: UnparsedSentence -> [PlayerName] -> Gbnf`. It narrows each non-verb list to the words the sentence names; verbs stay complete; a list the sentence names no word from stays full. It writes out the shapes of imperativeRules itself, so a shape added to Grammar/Parser/Composites/Rules.hs needs the same addition in generateGbnf.
- The GBNF's player names are acKnownPlayers plus this tick's NewPlayerJoined names (playerTickBlock). llama-server rejects a grammar with an empty rule (HTTP 400).
- Tables: slm (seeded rows 'qwen-Qwen3-1.7B-Q8_0' and 'slm-absent'), repair_failures, repair_successes. Both repair tables are records for study; the parse flow never reads them. Migration migrations/build/04-repair.sql, rollback migrations/rollback/95-repair.sql.
- Model: Qwen3-1.7B Q8_0 from the official Qwen/Qwen3-1.7B-GGUF repo. Flake let bindings slmPort = "8082", slmModel, slmName, llamaCppCuda. Shelpers start-slm-model and stop-slm-model, called from start-sashamud and stop-sashamud. VITE_SLM_PORT and VITE_SLM_NAME are set in the dev shell and the web derivation. llama-cpp 9925 has no --cors-origins flag.
- CI: sasha-e2e-wrapped runs the CPU llama-server with slmModel; SlmRepairSpec is the end-to-end test.
- hlint runs inside the build and fails it on hints.
