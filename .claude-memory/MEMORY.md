# SashaMud Project Memory

## CRITICAL RULES (re-read before every file write/edit)
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
- No WorldAccum intermediary needed — build GameState directly like IX
- IX reference: `eGameState = GameState <$> bAgentMap <*> bPlanetMap <@ eTick` then `reactimate`
- Signal functions: processJoinsSF >-> executeJoinsSF, gatherInputSF >-> processInputSF
- No TVar for GameState — lives in AccumT
- No naked types — use newtypes (SessionId, PlayerName, GameCommand)
- AppM is a newtype over ReaderT AppCtx Handler (like Quux)
- Server.Session removed — acConnections MVar replaces GameSessionRegistry
- deliverOutbound thread outside network reads acOutbound, routes via acConnections
- Login always sends PlayerJoined — network decides new vs returning player
- GID assignment is game-layer concern — counter in accumulator, not server
- Rhine tutorial: /home/mlitchard/github/rhine-tutorial

## IX EventNetwork Pattern
- GameState is OUTPUT, not input — built by the network from accumulated behaviors
- gameloop receives InitMaps (seeds), not GameState
- accumB seeds behaviors, GameState assembled on each tick
- reactimate sends GameState out after each tick
- One tick in IX; Rhine supports multiple ticks via |@| with AccumT
- Effects are part of the building computation — they contribute pieces to GameState

## GameState Lifecycle (from old code TopLevel.hs)
- GameState PERSISTS across turns — carries world state (agents, scenes, objects)
- Each turn: existing GameState provides the foundation, effect contributes on top of it
- New GameState = existing state + contributions from the effect
- Narration is extracted, delivered, then cleared for next turn (clearNarration)
- World state (agents, scenes) carries forward — NOT built from scratch each tick
- Flow: clear previous narration → run computation (contributes) → extract narration → deliver → clear → next turn
- Old code reference: sasha-engine/src/TopLevel.hs runGameWithInput (lines 123-149)

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
- Engine/Simulation/ consolidated: RhineM, signal functions, routing all in EffectNetwork.hs
  - Clocks.hs stays separate
- Session.hs removed: acConnections MVar replaces GameSessionRegistry
  - Authentication.hs handles auth pipeline instead
- SessionId lives in Model.Core (breaks circular import with WireProtocol)
- WireMessage.SessionId renamed to SessionAck (avoids name collision with SessionId type)

## Current State
- WebSocket message refactor DONE
- Ping/Pong through Rhine network — proves full pipeline works
- build-0 DONE: minimal dev env as root commit (branch: build-0-orphan)
- build-1 DONE: all existing code rebased on build-0 (branch: main, build-1)
- formatter = pkgs.nixpkgs-fmt + nix-formatting check added to flake.nix and .gitlab-ci.yml
- Commit 2 in progress: grammar package Step 1 + Step 2 done (Lexer, Atomics, Types)

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
- Do not touch files the user did not ask you to touch
- When editing a file, do NOT reformat surrounding content — preserve the user's formatting exactly
- Use minimal, targeted Edit calls — only change what was asked, leave everything else untouched
- NEVER write stubs, placeholders, or fake implementations
- DerivingVia needs the constructor in scope: import Foo (Foo) not just the type
- Use Data.Time.Calendar for Year (= Integer), MonthOfYear (= Int), Day, toGregorian — NEVER roll custom date types
- Check Hackage BEFORE inventing any type — if the standard library has it, use it
- ALL tests use hspec-discover — Main.hs is just `{-# OPTIONS_GHC -F -pgmF hspec-discover #-}`, never manual spec wiring
- NEVER run builds or tests unless user explicitly requests
- When user asks for commit message, give the TEXT — do not run git commit

## Key Files
- Architecture doc: /home/mlitchard/gitlab/sashamud/docs/monorepo-redesign.md
- Commit-1 doc: /home/mlitchard/gitlab/sashamud/docs/roadmap/commit-01-working-mud.md
- Feature ordering: /home/mlitchard/gitlab/sashamud/docs/roadmap/feature-ordering.md
- Old code: /home/mlitchard/gitlab/sasha/ (patterns, not gospel)
- Rhine source: /home/mlitchard/github/rhine
- Rhine koans: /home/mlitchard/github/rhine-koans
- Quux server (DB patterns): /home/mlitchard/gitlab/quux/server
- Memory: /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md (NOT the auto directory with - prefix)
