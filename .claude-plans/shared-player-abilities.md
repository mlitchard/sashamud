# Shared player abilities, and get and drop for the ball

Branch: 14-get-drop-ball-dsl. Written 2026-10-15.

## Goal

Players can get and drop the red ball in the lobby. The DSL code that adds
it is deployed to the live server with the token a player receives at
login.

## Ruling (user, 2026-10-15)

Players who already exist must gain new abilities when a wizard deploys
DSL. Each player keeps their own state. The world holds one shared set of
player abilities. Every ability lookup checks the agent's own keys first,
then the shared set. NPCs follow the same order, which is acceptable.

## Step rule (user, 2026-10-15)

Every step builds and its checks are green on its own. Any fix a step
needs (imports, exports, callers, instances, tests) lands in that same
step. No step relies on a later step to repair it.

## What exists today

- Grammar, engine, builder and DSL names for get and drop are complete.
  `eval` dispatches to `runActionProtocol @AcquisitionF` and
  `@DivestmentF` (sasha/src/Engine/ActionDiscovery/Instances.hs). The
  engine moves the ball between floor, inventory and scene itself.
- Get runs a veto chain over player, scene, floor (support) and ball. Drop
  runs one over player, ball, scene and floor (target). Each party needs a
  key.
- The player-side key is read in `fetchAgentAction`
  (sasha/src/Engine/ActionDiscovery/Protocol.hs). Witness keys are read in
  `processWitnesses` (sasha/src/Engine/Resolution/ActionManagement.hs).
- A live DSL run starts from the running GameState (`dslTickSF`). A
  returning player gets their stored agent unchanged (`processJoinsPure`).

## Precedent

- Old `overlay` (sasha-dsl/src/DSL/Capabilities/Core.hs:56): specific
  behaviours replace defaults.
- Old `findDVRoleKey` (sasha-engine/src/GameState/ActionManagement.hs:1673):
  specific key first, generic key through `<|>`.

## Decisions

1. Placement of the shared set: RULED B (user, 2026-10-15). Two fields on
   `World`, beside `_agentMap`.
2. Names: RULED (user, 2026-10-15).
   - `World` fields: `_sharedActionManagement :: ActionManagementFunctions`
     and `_sharedWitnessManagement :: Map VerbKey (GID WitnessF)`. Lenses
     `sharedActionManagement`, `sharedWitnessManagement`.
   - Constructors: `SharedBehavior :: ActionManagement -> SashaLambdaDSL ()`
     and `SharedWitnessBehavior :: VerbKey -> GID WitnessF -> SashaLambdaDSL ()`.
   - Wrappers: `sharedBehavior`, `sharedWitnessBehavior`.
3. Held items.
   - Actor message text: RULED (user, 2026-10-15). `StaticNarration "You
     pick up the ball."` and `StaticNarration "You drop the ball."`, linked
     to the ball's own get and drop keys.
   - Release order: RULED Order 1 (user, 2026-10-15). Steps 1 and 2 ship
     and the live server is redeployed with them. Get and drop then reach
     the running server through the token deploy of the two Step 3 files.
     The next server release carries those files.
   - File locations: RULED (user, 2026-10-15). World-wide files in
     `sashamud-world/src/1/World/`, the lobby in `sashamud-world/src/2/Lobby/`.
   - `dslServerUrl` stays local (user, 2026-10-15).
   - `deploy-dsl` takes `local` or `live` as its first argument (user,
     2026-10-15). `local` uses `dslServerUrl`; `live` uses
     `liveDslServerUrl = "https://sashamud.net"` (user, 2026-10-15; deploys
     repo services/sashamud.nix:98 and :104-105 route `/api/*` on that host
     to localhost:8081). The name follows `liveOidcBaseUrl` and
     `liveOidcRedirectUri`. `SASHA_URL` still overrides. An unknown target
     stops with a usage message. `start-sashamud` passes `local`.

## Step 1: shared set (Opus, one buildable step)

- sasha/src/Model/Core.hs
  - `World` gains `_sharedActionManagement` and `_sharedWitnessManagement`.
  - `defaultWorld` (Core.hs:504), the only `World` construction, gains
    `ActionManagementFunctions mempty` and `mempty`.
  - The hand-written `instance NFData World` (Core.hs:277) matches fields
    by position: add the two new fields to the pattern and `rnf` them.
    `World` derives `Eq, Ord, Show`; `Agent` already derives those and
    `NFData` for the same two field types.
- sasha/src/DSL/Model/EDSL/SashaLambdaDSL.hs
  - Constructors `SharedBehavior` and `SharedWitnessBehavior`. Wrappers
    `sharedBehavior` and `sharedWitnessBehavior`, exported.
- sasha/src/DSL/Builder.hs
  - `SharedBehavior key`: insert `key` into
    `bsGameState . world . sharedActionManagement . actionManagementFunctions`,
    the way `RegisterSpatial` writes through `world`.
  - `SharedWitnessBehavior verbKey gid`: insert into
    `bsGameState . world . sharedWitnessManagement`.
- sasha/src/DSL/Reify.hs
  - Add `sharedBehavior` and `sharedWitnessBehavior` to the
    `DSL.Model.EDSL.SashaLambdaDSL` list.
- sasha/src/Engine/ActionDiscovery/Protocol.hs
  - `fetchAgentAction`: the agent's `lookupActionGID` result, then `<|>`
    the same lookup on `world . sharedActionManagement`.
- sasha/src/Engine/Resolution/ActionManagement.hs
  - `processWitnesses`: the agent's witness entry for the verb, then `<|>`
    the entry in `world . sharedWitnessManagement`.
- Imports and exports, all in this step:
  - Core.hs export list carries the two new fields and their lenses.
  - SashaLambdaDSL.hs export list carries both wrappers; the GADT export
    already covers the constructors.
  - Builder.hs imports `sharedActionManagement`, `sharedWitnessManagement`
    and the two constructors.
  - Protocol.hs imports `sharedActionManagement` and `<|>`.
  - ActionManagement.hs imports `sharedWitnessManagement` and `<|>`.
  - Before writing, read SashaPrelude's export list for `<|>` and every
    other prelude name used, and the sasha cabal stanza for extensions in
    force. Instances.hs already uses `<|>`; its import is the model.

## Step 2: world restructure (Opus, ships with Step 1)

World-wide files load before rooms (user, 2026-10-15). `worldPrograms`
sorts, so `1/World` loads before `2/Lobby`.

- Move `sashamud-world/src/1/Lobby/1-lobby.dsl`, `2-floor.dsl`,
  `3-ball.dsl` to `sashamud-world/src/2/Lobby/`, contents unchanged.
- No code names `1/Lobby`. The flake (`worldDir`, flake.nix:160),
  `SASHA_WORLD_DIR`, BuilderSpec and hie.yaml name only
  `sashamud-world/src`. MEMORY's Live DSL section is updated to the new
  paths.
- flake.nix: `liveDslServerUrl` let binding; `deployDsl` reads the target
  from its first argument, and its usage message (flake.nix:174) names
  both arguments. Every caller passes `local` in this step: the
  `start-sashamud` loop (flake.nix:419) and the VM test's three calls
  (flake.nix:770, 771, 772). CI only builds the app (.gitlab-ci.yml:17,
  :171) and needs no change.

## Step 3: get and drop files, deployed live (Opus writes, after the live server runs Steps 1 and 2)

- `sashamud-world/src/1/World/1-get-drop.dsl`: player side, any room.
  Player get and drop actions (`getF`, `dropF`), keys
  `createAVTargetManagement getAV` and `createDVManagement dropDV` added
  with `sharedBehavior`. A fresh `declareWitnessGID witnessF`, with
  `sharedWitnessBehavior (AcquisitionKey getAV)` and
  `sharedWitnessBehavior (DivestmentKey dropDV)`.
- `sashamud-world/src/2/Lobby/4-get-drop-ball.dsl`: lobby side.
  `modifyScene (SceneLabel "lobby")` adds `createAVTargetManagement getAV`
  and `createDVManagement dropDV`. `modifyObject (ObjectLabel "floor")`
  adds `createAVSupportManagement getAV` and
  `createDVSurfaceManagement dropDV`. `modifyObject (ObjectLabel "ball")`
  adds `createAVTargetManagement getAV` and `createDVManagement dropDV`.
  `linkWorldOutcomeEffect` attaches `StaticNarration "You pick up the
  ball."` and `StaticNarration "You drop the ball."` to the ball's keys.
- Each key gets its own declared action, the way look is wired.
- Integration test in LoginLogoutSpec (Opus, user-ordered 2026-10-15),
  landing with the two files so the step is green. Two players connect.
  The first sends `get ball` and receives "You pick up the ball."; the
  second receives "<first> picks up the ball.". The first sends `look`
  and the "You see:" line has no ball. The first sends `drop ball` and
  receives "You drop the ball."; the second receives "<first> drops the
  ball.". It witnesses the shared-set fallback, since neither player's
  own agent carries get or drop keys.
- Deploy, in order:
  `SASHA_TOKEN=<token from settings> nix run .#deploy-dsl -- live sashamud-world/src/1/World/1-get-drop.dsl`
  then the same for `sashamud-world/src/2/Lobby/4-get-drop-ball.dsl`.
  New accounts get the `wizard` role (Authentication.hs:359); the route
  checks that role's Dsl permission.
- The next server release carries both files; restarts load them in
  order.
