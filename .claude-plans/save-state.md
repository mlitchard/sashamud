# Save State

Written 2026-10-17. Branch: save-state. Executor: sashamud-47 (user order 2026-10-17).

## Goal

A save covers the entire mud: every object, agent and scene. A save happens when a player logs out and when a player logs in. A load happens when the mud starts up: the world files are folded first, then the saved play state is merged on top.

## User rulings

- 2026-10-12: the sources for this task are sashamud and quux.
- 2026-10-17: a save covers the entire mud, all objects, agents and scenes.
- 2026-10-17: saves happen when players log out and when players log in.
- 2026-10-17: load is in this task. Loads happen at startup. The DSL files are folded first, then the save is applied.
- 2026-10-17: load on login is dropped. The live GameState is the one truth while the server runs.
- 2026-10-17: files are taken one at a time, O(1) in file text.
- 2026-10-17: all or nothing at startup. On a failed file the mud stops with a log line naming the last success and the failed file. The stop decision lives outside the signal network.
- 2026-10-17: the startup load runs from startup itself, with no wizard endpoint. Each step is tested as it lands.
- 2026-10-17: any .dsl file can be edited. At startup the files win for structure and dispatch, the save wins for play state, and scene and object GIDs are remapped through the labels.
- 2026-10-17: a returning player whose saved scene no longer exists lands in the lobby. The lobby is `newUserStartScene`.
- 2026-10-17: a wizard is a player holding the Dsl permission, acting on their own world. No guard protects them from themselves.
- 2026-10-17: sashamud-47 executes the plan.

## Follow-on tasks, after this one

- A DSL constructor that moves an agent to a scene. The lobby is the only target for now.
- Closing a scene while it is worked on. The flag arrives with the movement verb that reads it.
- Group delivery: several live amendment files landing as one fold, all or nothing, with the failure reported to the submitter. dslTickSF commits each file on its own today.

## What exists today

### The state

sasha/src/Model/Core.hs

- `GameState` (line 443) holds `_world`, `_narrationMap`, `_evaluation`, `_agentLocationMap`, `_actionMaps`, `_possibilityGraph`.
- `World` (line 272) is plain data: `_objectMap`, `_sceneMap`, `_globalSemanticMap`, `_agentMap`, `_sharedActionManagement`, `_sharedWitnessManagement`, `_spatialRelationshipMap`, `_declaredSceneGIDs`, `_declaredObjectGIDs`. It derives stock Eq, Ord, Show and has a hand-written NFData instance.
- `_agentLocationMap :: Map (GID Agent) (GID Scene)` is plain data.
- `_evaluation`, `_actionMaps` and `_possibilityGraph` hold functions built by the DSL fold. `_evaluation` gains an entry per player at NewPlayerJoined (SignalNetwork.hs line 404). `_possibilityGraph` holds `_newUserStartScene :: Maybe (GID Scene)`.
- `Object` (line 208), `Agent` (line 218), `ActionManagement` (line 155), `ActionManagementFunctions` (line 165), `AgentKind` (line 201) and `Narration` (line 298) derive FromJSON and ToJSON.
- `Scene` (line 235), `EntityID` (line 252), `SpatialRelationship` (line 258), `SceneLabel` (line 191) and `ObjectLabel` (line 195) have no JSON instances.
- `GID` (Model/GID.hs line 16) derives newtype FromJSON and ToJSON. `Mid` (Model/Mid.hs line 20) derives newtype FromJSONKey and ToJSONKey as well.
- Every GID is minted by the fold in file order. Scenes and objects are also named by label in `_declaredSceneGIDs` and `_declaredObjectGIDs`. Function GIDs have no label. A player's agent GID is the account's user_id (Server/Authentication.hs line 305).

sasha/src/Server/App.hs

- `BuilderCounters` (line 90) holds seven `PInt` counters. `PInt` (line 78) derives stock Eq, Ord, Show. Its constructor is hidden outside the module.
- `AppCtx` (line 153) holds `acBuilderCounters :: IORef BuilderCounters`, `acKnownPlayers :: MVar (Map PlayerNameVAL (GID Agent))`, `acDbPool :: Pool Connection`. `newAppCtx` takes the counters.
- acKnownPlayers is filled only by `executeJoinIO` on NewPlayerJoined (SignalNetwork.hs line 628). After a restart it is empty, so `processJoinsPure` (line 355) classifies every player as new.
- `joinComputation (ReturningPlayerJoined ...)` (line 365) puts the agent in its scene and registers no evaluator. `joinComputation (NewPlayerJoined ...)` (line 383) registers `Evaluator eval`.

### Startup

- `startServer :: WorldBuilderResult -> IO ()` (Server/Server.hs line 149): pool, migrations, OIDC config, `newAppCtx logCfg pool oidcConfig manager (resultCounters result)`, the opt-in bootstrap mint, then `race_ (race_ (gameLoop ctx (resultGameState result)) (deliverOutbound ctx)) (run port (app ctx))`. Nothing listens before that `race_`.
- `main = startServer (WorldBuilderResult defaultGameState initialCounters [])` (sashamud-server/app/Main.hs).
- `loadWorld :: FilePath -> ExceptT WorldLoadFailure IO WorldBuilderResult` (Server/World.hs) lists the files with `worldPrograms` and folds them from `WorldBuilderResult defaultGameState initialCounters []`. The fold reads, decodes, reifies and builds one file per iteration. `WorldLoadFailure` is `WorldDecodeFailed UnicodeException | WorldReifyFailed InterpreterError | WorldBuildFailed WorldBuilderError`. `worldLoadFailureText` renders it.
- The sasha-server wrapper sets `SASHA_WORLD_DIR` with `--set-default` (flake.nix line 564). The dev shell, the test shells and both VM tests set it too.

### Delivery today

- start-sashamud (flake.nix line 411) mints the bootstrap token, creates the wizard account, waits for the token file and the port, loops `deploy-dsl local` over `find "$SASHA_WORLD_DIR" -name '*.dsl' | sort`, logs out, removes the token file.
- run-deploy-tests (flake.nix line 786) loops deploy-dsl over worldDir, then delivers study.dsl and amend-lobby.dsl, then logs out.
- run-end-to-end (flake.nix line 829) delivers nothing itself. SeleniumHarness `withServer` (sashamud-server/test-e2e/SeleniumHarness.hs line 129) seeds a Bootstrap wizard, logs in through the fake provider, posts each worldPrograms file to /api/game/dsl, sleeps six seconds, logs out. LoginLogoutSpec `withTestServer` (sashamud-server/test/Integration/LoginLogoutSpec.hs line 225) does the same through the servant client. Both call `gameLoop ctx defaultGameState` and `newAppCtx ... initialCounters` directly.
- `dslHandler` (Server/Server.hs line 118) reifies the body and writes `Routed sessionId dsl` to acDSLChan. `dslTickSF` (SignalNetwork.hs line 214) drains the channel every five seconds and folds from `WorldBuilderResult gs counters []`. This is the live amendment path and stays as it is.

### Logout, login, the tick

- `logoutHandler` (Server/Server.hs line 110) deletes the token row and the session. The websocket close handler (Server/GameWebSocket.hs line 39) deletes the session. GameState is untouched by both.
- `processLeavesPure` (SignalNetwork.hs line 326) runs every PlayerTick, removes agents that are known and have no InGame session from `sceneAgents`, and announces. The location entry stays. The departed set is computed inside the computation and never returned. Because it runs first in `composeTick`, a player who logs out is already out of `sceneAgents` when that tick's save is written.
- `processJoinsPure` returns `([JoinResult], GameComputation Identity ())`.
- `playerTickBlock` (line 236) is the one writer of GameState. The repair rows (lines 272 to 289) are the sashamud pattern for a database write in the tick: `try . withResource (acDbPool appCtx) $ \conn -> insertRepairFailure conn ...`, `Left err` to stderr.

### Storage

- Migrations: migrations/build 000000-auth through 000004-repair, migrations/rollback 999999-auth down to 999995-repair. The next pair is 000005 and 999994.
- Typed columns with hand-written ToField and FromField: AccountStatus, AllowedAction, RoleName. Newtype deriving for RoleId, AuthentikUserId, Mid, Jwt.
- quux JSON column: `SOI` (quux src/Model/SignalOfInterest.hs line 99) derives `ToField` via `Aeson SOI` from `Database.PostgreSQL.Simple.Newtypes`, and its `FromField` decodes the bytes with `decode` and answers `ConversionFailed` on a bad decode. quux's JSON columns are `jsonb` (migrations/build/03-Notifications.sql).
- A write with several statements in one `execute`: quux Model/Jwt.hs line 81, sashamud Model/Jwt.hs line 94.

## The merge at startup

Inputs: the fresh `WorldBuilderResult` from the file fold, the latest `WorldSave`, and the credentials rows (player_name, user_id).

- Scene remap: for each label in the saved `_declaredSceneGIDs` that the fresh `_declaredSceneGIDs` also has, saved GID to fresh GID. Object remap: the same over `_declaredObjectGIDs`.
- Player agents: the saved `_agentMap` entries whose GID is a user_id from credentials. They are inserted into the fresh `_agentMap`. NPC agents come from the files.
- Locations: each saved `_agentLocationMap` entry for a player agent, with its scene GID remapped. A scene with no remap becomes the fresh `_newUserStartScene`. A fresh world with no `_newUserStartScene` is a load failure.
- Scene membership: `_sceneAgents` comes from the files. A save written at logout has the departed player already out, and after a restart nobody is online. Returning players enter `_sceneAgents` through the join.
- Spatial map: each saved `_spatialRelationshipMap` entry whose entity remaps (an object by label, or a player agent) is kept with every GID inside it remapped. An entry that names an entity with no remap is dropped. Entries from the files for entities the save does not mention stay.
- Everything else, `_objectMap`, `_sceneMap`, `_globalSemanticMap`, `_sharedActionManagement`, `_sharedWitnessManagement`, the declared maps, the counters, the action maps and the possibility graph, comes from the files.
- acKnownPlayers is seeded with the credentials rows whose user_id has a saved agent. A credentials row with no saved agent is a player who never connected, and that player joins as new.
- To check while writing step 4: whether the acquisition and divestment effects touch `_sceneObjects` as well as the spatial map. If they do, `_sceneObjects` joins the play state and merges the same way.

## Decisions

1. Trigger inside the tick. The save runs in playerTickBlock's IO phase after the computation, on a tick where a player joined or departed. Joins are `joinResults`. Recommendation: `processLeavesPure` takes the generator shape of `processJoinsPure`, returning `([GID Agent], GameComputation Identity ())` with the departed agents as the data. It takes `gs` as an argument for the scene sweep, the way `resolveCommands` takes its inputs, and the computation body keeps its `get`. A disconnect without a logout looks the same to the chain and also saves.

2. What is written. The `World` from gs', the `_agentLocationMap` from gs', and the `BuilderCounters` from acBuilderCounters. The whole mud is written. The merge at startup chooses what it takes.

3. Column shape. Recommendation: one record holding the three parts, one `jsonb` column, one row per save, following quux's SOI. Table `saves` with `save_id`, `saved_at`, `state`. The record derives FromJSON and ToJSON, `ToField` via `Aeson`, and a hand-written `FromField` that decodes with `decode` in the SOI shape.

4. JSON instances, in the deriving style Core.hs already uses. Scene, EntityID, SpatialRelationship: `deriving anyclass (FromJSON, ToJSON)`. World: Generic added to the stock list, `deriving anyclass (FromJSON, ToJSON)`. GIDToDataMap, AgentMap, SpatialRelationshipMap: `deriving newtype (FromJSON, ToJSON)`. GID: FromJSONKey and ToJSONKey added to the newtype list, as Mid has. SceneLabel, ObjectLabel: FromJSON, FromJSONKey, ToJSON, ToJSONKey added to the newtype list. EntityID: `deriving anyclass (FromJSONKey, ToJSONKey)` as well, since it keys the spatial map. PInt: `deriving newtype (FromJSON, ToJSON)` inside Server/App.hs. BuilderCounters: Generic and `deriving anyclass (FromJSON, ToJSON)`.

5. Names. Table `saves`. Migration files `000005-save.sql` and `999994-save.sql`. Record `WorldSave` with fields `_saveWorld`, `_saveAgentLocations`, `_saveCounters`. `insertSave :: Connection -> WorldSave -> IO ()`, `loadSave :: Connection -> IO (Maybe WorldSave)`, and the pure merge `applySave :: Map PlayerNameVAL (GID Agent) -> WorldSave -> WorldBuilderResult -> Either WorldLoadFailure WorldBuilderResult`, all in Server/World.hs beside loadWorld. Names are the user's to change.

6. Startup sequence in startServer. After migrations: read `SASHA_WORLD_DIR` (unset is a stderr line and exitFailure, as the harness does), `runExceptT (loadWorld dir)`, read the credentials rows, `loadSave` through the pool, `applySave` when a row exists, on any Left write the failure through writeLog and exitFailure, then `newAppCtx` with the result's counters, seed acKnownPlayers, then the existing `race_`. `startServer :: IO ()` and `main = startServer`. The two harnesses run the same sequence before `gameLoop` and drop their Bootstrap login, delivery loop, sleep and logout.

7. The failure log line. `WorldLoadFailure` constructors each gain the failed `FilePath` and the last successful `Maybe FilePath`. The fold in loadWorld carries the last successful path beside the result. `worldLoadFailureText` prints both. A new constructor covers a fresh world with no `_newUserStartScene` at merge time. A new `LogEntry` constructor carries the failure for writeLog.

8. Returning players. `joinComputation (ReturningPlayerJoined ...)` also sets `evaluation . at gid ?~ Evaluator eval`, so a returning player after a load has an evaluator. The lobby fallback for a missing scene happens in the merge, so the join path finds every returning player's scene.

9. Scripts. start-sashamud and run-deploy-tests lose the world delivery loop. The bootstrap mint, account creation, study.dsl and amend-lobby.dsl delivery, logout and token removal stay. The harnesses clear the saves table before loadSave, so a row from an earlier run never leaks into a test.

10. Tests, one per step: roundtrip props for the new JSON types; insertSave then loadSave round trip; a login and a logout each write a saves row; applySave puts a saved player back in its saved scene by label, sends a player whose scene is gone to the lobby, and keeps a saved inventory entry remapped; a bad file stops startup with the log line naming the last success and the failed file; a returning player after a load lands in the saved scene and a look narrates it.

## Steps

Step rule: every step builds and is green on its own. Any fix a step needs, including imports, exports, callers, instances and tests, lands in that step.

### Step 1. JSON instances

Files: sasha/src/Model/Core.hs, sasha/src/Model/GID.hs, sasha/src/Server/App.hs, the JSONSpec file in sasha's test tree.

- The deriving clauses from decision 4.
- Core.hs and GID.hs import `FromJSONKey` and `ToJSONKey` from Data.Aeson.
- Arbitrary instances under `#ifdef TESTING` for each type that gains JSON, in the GenericArbitrary style Core.hs uses, and the JSONSpec prop lines.

### Step 2. Migration and the save record

Files: migrations/build/000005-save.sql, migrations/rollback/999994-save.sql, sasha/src/Server/World.hs, sasha/sasha.cabal if a dependency is missing.

```sql
DROP TABLE IF EXISTS saves CASCADE;
CREATE TABLE saves
  ( save_id SERIAL CONSTRAINT savespk PRIMARY KEY
  , saved_at timestamp with time zone NOT NULL
  , state jsonb NOT NULL
  );
```

Rollback: `DROP TABLE IF EXISTS saves CASCADE;`

- `WorldSave` record, `deriving stock (Eq, Generic, Show)`, `deriving anyclass (FromJSON, ToJSON)`, `deriving (ToField) via Aeson WorldSave`, a hand-written `FromField WorldSave` in the SOI shape, `makeLenses ''WorldSave`.
- `insertSave conn save` runs `INSERT INTO saves (saved_at, state) VALUES (now(), ?)` with `execute`.
- `loadSave conn` runs `SELECT state FROM saves ORDER BY save_id DESC LIMIT 1` with `query_`, answers `Nothing` on no row and `Just` on a row.
- Test: an integration test writes a `WorldSave` with insertSave and reads it back with loadSave, equal.

### Step 3. The save in the tick

File: sasha/src/Engine/Simulation/SignalNetwork.hs.

- `processLeavesPure` takes the generator shape from decision 1. playerTickBlock binds `(departed, leavesComp) = processLeavesPure gs sessions known`.
- After the narration delivery and before the state views:

```haskell
    when (not (null joinResults) || not (null departed)) $ do
      counters <- liftIO $ readIORef (acBuilderCounters appCtx)
      written :: Either SqlError () <- liftIO . try . withResource (acDbPool appCtx) $ \conn ->
        insertSave conn (WorldSave (view world gs') (view agentLocationMap gs') counters)
      case written of
        Left err -> liftIO $ hPutStrLn stderr ("Save not written: " <> show err)
        Right () -> pure ()
```

- Test: in LoginLogoutSpec, a login then a logout leaves two rows in saves, and the last row's agentLocationMap holds the player's GID at the lobby.

### Step 4. The load at startup

Files: sasha/src/Server/Server.hs, sasha/src/Server/World.hs, sasha/src/Server/Log.hs, sashamud-server/app/Main.hs, sashamud-server/test-e2e/SeleniumHarness.hs, sashamud-server/test/Integration/LoginLogoutSpec.hs, flake.nix.

- `WorldLoadFailure` and `worldLoadFailureText` from decision 7. The `LogEntry` constructor for the startup failure.
- `applySave` from the merge section.
- startServer from decision 6. Main.hs becomes `main = startServer`.
- Both harnesses: clear saves, `runExceptT (loadWorld dir)`, credentials rows, `loadSave`, `applySave`, `newAppCtx` with the result's counters, seed acKnownPlayers, `gameLoop ctx` with the result's GameState. The Bootstrap login, delivery loop, sleep and logout go.
- flake.nix: the world loop goes from start-sashamud and from run-deploy-tests.
- Tests: the applySave cases from decision 10; a bad file makes startup stop with the log line naming the last success and the failed file.

### Step 5. Returning players after a load

Files: sasha/src/Engine/Simulation/SignalNetwork.hs, sashamud-server/test/Integration/LoginLogoutSpec.hs.

- `joinComputation (ReturningPlayerJoined ...)` sets the evaluator.
- Test: a player logs in and out, the harness restarts the loop from loadWorld, loadSave and applySave against the same database, the player logs in again and lands in the saved scene, and a look narrates it.
