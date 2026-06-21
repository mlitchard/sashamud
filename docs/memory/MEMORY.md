# SashaMud Project Memory

## Project Vision
- **SashaMud**: MUD engine + software engineering pedagogy tool
- Commit history IS pedagogy — each commit teaches one concept

## Monorepo Structure (2026-06-21)
- **Architecture doc**: `/home/mlitchard/gitlab/sashamud/docs/monorepo-redesign.md` (SUBJECT TO CORRECTION — living document, verify before treating as settled)
- 4 packages in one repo: sasha-grammar, sasha-vocabulary, sasha, sashamud-world
- Grammar types (Lexeme, Sentence, verb/noun types) live in sasha-grammar, NOT in core
- World-model types (GID, GameState, Agent, etc.) live in sasha (Model/)
- Engine split: Engine/Resolution/ (action resolution) + Engine/Simulation/ (Rhine living world)
- DSL/Capabilities/ is DEAD — replaced by 3 Has* classes + plain functions
- RichText uses Clay.Color instead of homemade TextColor enum
- GitLab group: `liftlatch/sashamud`

## Server Architecture (Blueprint is authoritative)
- Blueprint: `/home/mlitchard/gitlab/sashamud/docs/architecture/rhine-architecture-blueprint.md`
- Monad stack: RhineM (GameStateT GameChan) where GameChan = EventChanT GameEvent (ReaderT AppCtx IO)
- GameState lives in GameStateT inside RhineM — Rhine's `flow` maintains it across ticks
- GameState is NOT in AppCtx and NOT in a TVar
- AppCtx holds boot-time data only (PossGraph, TVar clients, TVar playerMap, TChan commandChan, GameLog)
- `hoistComputation` bridges pure GameComputation Identity to GameComputation GameChan
- `runComputation` unwraps the hoisted computation inside RhineM — same GameStateT, no extraction/reinsertion
- EventChanT provides EventClock for GameEvent Behaviors (gameEventSF)
- Test executables with hspec, wired into flake checks

## Nix Flake Patterns
- Rhine: `fetchFromGitHub` turion/rhine + `callCabal2nix` for rhine, automaton, monad-schedule, time-domain. Also needs changeset, monoid-extras, simple-affine-space, selective, foldable1-classes-compat
- `mapAttrs (_: hlib.dontCheck)` wrapping overlay
- Library build checks: `pkgs.runCommand` with `buildInputs`
- Executable test checks: `pkgs.runCommand` with `${pkg}/bin/test-name`

## Key Patterns
- Phantom-typed GID (newtype GID a = GID Int, role phantom)
- GADT-based DSL with Pure/Map/Apply/Bind + domain constructors
- Test stanzas use `executable`, NOT `test-suite`
- Tests use hspec-discover
- Tests MUST execute during `nix flake check`

## Architecture
- **Architecture doc**: `/home/mlitchard/gitlab/sashamud/docs/monorepo-redesign.md` (SUBJECT TO CORRECTION — living document, verify before treating as settled)
- 4 packages in one repo: sasha-grammar, sasha-vocabulary, sasha, sashamud-world
- Grammar types (Lexeme, Sentence, verb/noun types) live in sasha-grammar, NOT in core
- World-model types (GID, GameState, Agent, etc.) live in sasha (Model/)
- Engine split: Engine/Resolution/ (action resolution) + Engine/Simulation/ (Rhine living world)
- DSL/Capabilities/ is DEAD — replaced by 3 Has* classes + plain functions
- RichText uses Clay.Color instead of homemade TextColor enum

## Roadmap
- Commit-1 restructured: player login and heartbeat
- Roadmap directory: `/home/mlitchard/gitlab/sashamud/docs/roadmap/`
- Commit-1 doc: `/home/mlitchard/gitlab/sashamud/docs/roadmap/commit-01-working-mud.md`
- Next session: write the rest of the roadmap (commit 2 onward)
- Original commit-1 spec (5-repo, for intent reference only): `/home/mlitchard/gitlab/sashamud/attic/docs/commits/commit-01-working-mud.md`

## Critical Rules
- **NEVER EXTRAPOLATE** — do NOT add, assume, or fill in details the user did not say. If the user says "login and heartbeat", that means login and heartbeat — not agents, not scenes, not parsers, not anything else. Ask if unclear.
- **RESPECT FILE FORMATTING** — approximate 80 characters per line, without breaking up words. Do NOT reformat existing content — this applies to new content only.
- **ONLY DO WHAT IS ASKED**
- **WRITE TESTS WITH MODULES** — never skip
- Never qualify imports (EXCEPTION: qualified Model.Core as Core in DSL/Vocabulary.hs)
- Always explicitly import constructors (no `(..)` wildcards)
- Never use wildcard `_` patterns, never use `~` (tilde/lazy)
- Always include type signatures
- Never import from Prelude or GHC.Base — use SashaPrelude
- No raw tuples for domain types — always records
- ALL game behavior through effect system
- Use lens English names (view, set, over, use, assign, modifying)
- For anything SashaPrelude does not export, STOP AND ASK

## User Preferences
- "make a prompt" means SHOW the prompt text on screen, not just save it
- Memory files go in `/home/mlitchard/gitlab/sashamud/docs/memory/`, NOT in `.claude/` directories
