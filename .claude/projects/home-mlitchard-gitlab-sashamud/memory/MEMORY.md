# SashaMUD Project Memory

## CRITICAL RULES
- NEVER qualify imports. If a conflict arises, STOP and ask.
- Always explicitly import constructors (no (..) wildcards).
- Never use wildcard _ patterns in pattern matching.
- Never use ~ (tilde/lazy) — NFData for all data/newtypes.
- Always include type signatures.
- mapM_ from Data.Foldable, never GHC.Base.
- Never import from Prelude or GHC.Base — use SashaPrelude. For anything SashaPrelude doesn't export, STOP and ask.
- NoImplicitPrelude in every .hs file. Always import SashaPrelude.
- SashaPrelude is based on attic/core/src/SashaPrelude.hs — follow that pattern exactly.
- Do not extrapolate or add scope without asking.
- "Stop inventing" means: do NOT create helpers, abstractions, convenience wrappers, or any code pattern that does not already exist in the old codebase at /home/mlitchard/gitlab/sasha/. If a pattern is needed, find it in the old code first. If it doesn't exist there, STOP and ask. Never assume you know better than the existing code.
- NEVER run builds or tests. The user runs builds. The user pastes errors. You fix them. This is not optional.
- No Maybe Color — Color is always explicit. No plain, no defaultStyle. Every span gets its color from the DSL.
- TSConstructName orphan instances for external types (like Color -> "string") follow quux Orphans.hs pattern.
- TMChan for message bus (inbound MessageFrom, outbound MessageTo). No per-client TChan/outbox.
- TMVar for thread communication (sendMsgs callback). No TVar (Maybe ...).
- SessionId (Text) is the primary identifier for player sessions, not ClientName/ByteString.
- WebSocket is bidirectional: Text in (commands), WireMessage out (responses). No separate GameCommandAPI.
- AuthProtect SecWebSocketProtocol on the WebSocket route. Always succeeds in build-1.
- GameSessionRegistry lives in AppCtx.
- async package for thread management, not forkIO.

## Architecture
- 4 packages: sasha-grammar, sasha-vocabulary, sasha, sashamud-world.
- See docs/monorepo-redesign.md for full layout
- See docs/roadmap/commit-01-working-mud.md for build-1 spec
- Old code at /home/mlitchard/gitlab/sasha/ for patterns
- Quux at /home/mlitchard/gitlab/quux/server/ for servant-websockets, AuthProtect, TSConstructName orphans, devShell
- IX at /home/mlitchard/github/ix/ for reactive EventNetwork pattern (gameloop, compile+actuate, Behaviors/Events)
- Attic at /home/mlitchard/gitlab/sashamud/attic/ for SashaPrelude, old core types
- Circular refs between Agent/Scene resolved by putting both in Model.Core (one file, like old code).
- Clay.Color for RichText (not TextColor enum).
- DSL uses free-monad-style GADT (Pure/Bind constructors give Monad instance).
- Rhine runs in RhineM. Signal functions are ClSF RhineM tick () (). GameState in the monad stack via StateT.
- PossibilityGraph is immutable after DSL construction.
- AppCtx: server concerns only. No GameState, no PossibilityGraph.
- EffectNetwork.hs: merged RhineM monad + Rhine pipeline + signal functions (follows IX EventNetwork single-module pattern).
- devShell uses mkShell + inputsFrom (shellFor with no packages), following quux pattern. Never build the project to enter the shell.

## Build-1 Status
Compiling. Remaining errors:
- MonadSchedule instance for RhineM (deriving newtype attempted)
- Clock RhineM instances for Millisecond clocks
- Various unused import warnings

## Dead files to remove
- Error.hs (invented throwMaybeM, nothing uses it)
- Model/RandomPool.hs (empty stub)
- Server/Log.hs (invented LogEntry type)

## Conventions
- GHC2021 language
- microlens-platform for lenses
- makeLenses TH in each module
- aeson-generics-typescript fork for TS codegen (derivingTypeScriptDefinition TH splices)
- horizon-platform for Nix Haskell package set (GHC 9.6.x)
- Rhine from turion/rhine GitHub (specific commit hash)
