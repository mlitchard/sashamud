# Build 1 Gap-Closing Plan

Gaps identified by audit against commit-01-working-mud.md spec.

---

## Gap 1: Lint Infrastructure

**Problem:** The flake imports `lint-utils`, defines `lu` and `lu-pkgs`, puts hlint and stylish-haskell in the devShell, but never defines lint checks. No `.hlint.yaml` or `.stylish-haskell.yaml` at project root. The old sasha project and quux both had full lint stages.

**Tasks:**

1. Copy `.hlint.yaml` from `attic/sasha/.hlint.yaml` to project root, adapt for current module structure
2. Copy `.stylish-haskell.yaml` from `attic/sasha/.stylish-haskell.yaml` to project root
3. Add three checks to `flake.nix`:
   - `cabal-formatting` via `lu.cabal-fmt`
   - `haskell-formatting` via `lu.stylish-haskell`
   - `haskell-linting` via `lu.hlint`
4. Add Lint stage jobs to `.gitlab-ci.yml`:
   - `Cabal Style`
   - `Haskell Formatting`
   - `Haskell Linting`
5. Run `nix flake check` to verify all lint checks pass
6. Fix any lint violations surfaced

---

## Gap 2: Server/Validator.hs

**Problem:** The spec lists input validation as a commit 1 concern. Login accepts player names but there is no validation module enforcing non-empty, length limits, or character whitelists.

**Tasks:**

1. Study validation patterns in old code (`sasha-web/server/`)
2. Create `sasha/src/Server/Validator.hs`:
   - `validatePlayerName :: PlayerName -> Either Text PlayerName`
   - Non-empty check
   - Length limit (e.g. 20 chars)
   - Character whitelist (alphanumeric + spaces, no control chars)
   - No profanity stub (just the interface, real filter is a later commit)
3. Add `Server.Validator` to `sasha.cabal` exposed-modules
4. Wire validation into the login handler in `Server.hs` or `Authentication.hs`
5. Return structured error on validation failure
6. Add unit tests in `test/Server/ValidatorSpec.hs`

---

## Gap 3: TypeScript Input Management

**Problem:** The frontend accepts user input in the command bar and login overlay but performs no client-side validation. Invalid input should be rejected before it hits the wire.

**Tasks:**

1. Study input handling in old sasha-web code (`sasha-web/web/apps/sasha-web/src/`)
2. Add validation to login overlay in `main.ts`:
   - Trim whitespace
   - Reject empty names
   - Enforce length limit (match server-side limit)
   - Reject disallowed characters
   - Show inline error message
3. Add validation to command input in `GameConnection.ts` or `createDOM.ts`:
   - Trim whitespace
   - Reject empty commands
   - Enforce max command length
4. Validation rules must match server-side rules in Validator.hs (single source of truth is the server; client mirrors them for UX)

---

## Gap 4: Integration Tests

**Problem:** The spec lists integration tests that verify the full login-to-heartbeat pipeline. Current test files are unit tests only. The NixOS VM test (`run-sasha-tests`) runs the `sasha-tests` executable, but that contains unit specs, not integration tests.

**Tasks:**

1. Determine test strategy: integration tests in `sasha/test/` (spin up server in-process) or in `sashamud-server/test/` (full stack, NixOS VM)
2. Write integration tests per spec:
   - POST `/api/game/login` with valid name returns sessionId
   - POST `/api/game/login` with empty name returns error
   - Returned sessionId connects successfully to WebSocket
   - Invalid sessionId on WebSocket connect is rejected
   - Login creates agent in `_agentMap` with correct `_agentShortName`
   - Login assigns agent to lobby scene (`_sceneAgents` contains agent GID)
   - Heartbeat delivery: connected client receives `SystemMessage` within 5s
   - Multi-player: two players login, both agents exist in lobby `_sceneAgents`
   - Multi-player: both clients receive heartbeats independently
   - Disconnect: agent removed from lobby scene and `_agentMap`
3. Add integration test executable to appropriate cabal file
4. Add NixOS VM test check to `flake.nix` if needed
5. Add CI job for integration tests

---

## Gap 5: Missing Unit Test Coverage

**Problem:** The spec lists unit tests that don't have corresponding spec files.

**Tasks:**

1. `test/SashaPreludeSpec.hs` — verify expected re-exports are available
2. Verify `test/Model/Core/GameStateSpec.hs` covers:
   - GameState default construction (lobby in sceneMap, `_gameStatus = Running`)
   - PossibilityGraph empty construction
3. Add Narration tests (mempty identity under `(<>)`) — either in GameStateSpec or new file
4. Verify `test/Model/Core/DefaultsSpec.hs` covers:
   - `defaultPlayerAgent` creates agent with correct name and scene assignment
5. Verify `test/Model/RichTextSpec.hs` covers:
   - Smart constructors (`plain`, `colored`, `bold`, `boldColored`) produce correct spans
   - `toPlainText` strips styling
6. Verify `sashamud-world/test/DSL/BuilderSpec.hs` covers:
   - `runWorldBuilder` produces GameState with lobby scene
7. Fill any gaps found

---

## Execution Order

1. **Lint infrastructure** (Gap 1) — foundational, catches issues in everything else
2. **Server/Validator.hs** (Gap 2) — needed before integration tests can test validation
3. **TypeScript input management** (Gap 3) — mirrors server validation
4. **Missing unit tests** (Gap 5) — fill coverage gaps
5. **Integration tests** (Gap 4) — full pipeline verification, depends on Validator being wired

---

## Not Gaps (Intentional Decisions)

- **Model/Core/ consolidated** into Core.hs + Mappings.hs (not split into 7 files)
- **Engine/Simulation/ consolidated** into EffectNetwork.hs + Clocks.hs (not split into 4 files)
- **Session.hs removed** — acConnections MVar replaces GameSessionRegistry, Authentication.hs handles auth pipeline
