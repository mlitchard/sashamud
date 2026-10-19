# GBNF dispatch grammar, look dispatch, lowercase intake

## Goal
`show me raj` is never repaired to `look at red ball`. Repair grammars are built from what the person asking can do and the scene they are in. Look dispatch follows old code's `runActionProtocol` with the three-gate check. All player sentences are lowercased at intake. The users table is the one source for "is a player".

## Rulings — all RULED (user, 2026-10-19)
1. Old code is the model. `manageAgentStimulusProcess` becomes `runActionProtocol @…`; its logic moves into an instance in `Instances.hs`.
2. Gate order: looking agent → scene → target. Gating happens at evaluation, outside the grammar.
3. `DSATargetManagementKey` is used by objects, agents as targets, and the scene. `ISATargetManagementKey` is used by the scene. The scene's `DSAManagementKey` and `ISAManagementKey` are removed. `DSAManagementKey`/`ISAManagementKey` live on the actor only.
4. Wrappers: `CreateDSATargetManagement`/`createDSATargetManagement`, `CreateISATargetManagement`/`createISATargetManagement`. Lookups: `lookupDirectionalStimulusTarget`, `lookupImplicitStimulusTarget`.
5. The player template's target key gets its own GID.
6. `fetchSceneActions` is ported: the actor's overlay merges over the scene's base table.
7. `Scene` mirrors the old definition except `_agentSemanticMap`. `sceneAgents` and `agentShortName` are the only source for naming an agent.
8. Every gate checks the entity's own table, then that kind's shared table, then `throwMaybeM` (programmer error).
9. Shared tables: `_sharedAgentActionManagement`, `_sharedObjectActionManagement`, `_sharedSceneActionManagement`. DSL: `SharedAgentBehavior`/`sharedAgentBehavior`, `SharedObjectBehavior`/`sharedObjectBehavior`, `SharedSceneBehavior`/`sharedSceneBehavior`, with `Reify` entries. `1-get-drop.dsl` uses `sharedAgentBehavior`. `_sharedWitnessManagement` is unchanged.
10. Get and drop keep their behaviour; only the shared-table structure changes.
11. Every sentence (`GameCommand` and `RepairedCommand`) is lowercased at intake in `resolveCommands`. The lexer does no case conversion: `toUpper` leaves `lexify`; `classify` literals are lowercase.
12. New lexeme `UNKNOWN Text`. An unknown word is promoted to `PLAYERNAME` when `users.player_name` matches it.
13. The lookup runs in the IO gather phase of `playerTickBlock`, one batched query, `status = 'active'`. Names: `PlayerLookup = PlayerWordsFound (Set PlayerName) | PlayerLookupFailed SqlError`, `playerLookupFailureText`, `selectPlayerWords`.
14. `users` is the one source for "is a player". `acKnownPlayers` is removed: grammar names come from `users`; joins decide new/returning by `agentMap` membership; a departure is a `users.user_id` with no live session.
15. Schema: `player_name` moves from `credentials` to `users` as `TEXT UNIQUE NOT NULL`. `credentials` takes no token column; `tokens.user_id` (UNIQUE, REFERENCES users) links a token to its account. RULED (user, 2026-10-19).
16. Account names are lowercased in `validate`; a migration lowercases existing names.
17. When the sentence holds a `PLAYERNAME` and none of the object words, `generateGbnf` narrows to `LOOK AT <player-name>`.
18. Repair-grammar verbs come from the actor's own table, then the shared agent table. Targets stay vocabulary-wide.
19. e2e `look at googly` becomes a name seeded but not in the scene, e.g. `bootstrap`.
20. Later: world agents need a GID source that cannot collide with `users.user_id`.
21. Step 2: the database is built fresh from `migrations/build/`. sashamud-d8 writes the next SQL file, `000006-player-name.sql`, and changes the code that reads `player_name` in the same step. RULED (user, 2026-10-19).
22. Step 1: sashamud-d8 writes the migration that lowercases existing `credentials.player_name` values.

## What exists today
- `sasha-grammar/src/Grammar/Gbnf.hs`: `generateGbnf`; `narrowed` empty falls back to full lists (:86); `named` uses `toUpper` (:100); stimulus rule has `LOOK AT <player-name>` (:65).
- `sasha-grammar/src/Grammar/Lexer.hs`: `lexify` applies `toUpper` (:101); `classify` catch-all is `PLAYERNAME w` (:128).
- `sasha-grammar/src/Grammar/Parser/Composites/Rules.hs`: `playerNameRule` (:154); `AgentStimulusVerbPhrase` (:149).
- `sasha/src/Engine/ActionDiscovery/Percieve/Look.hs`: `manageAgentStimulusProcess` (:69–142), inline actor lookup with no shared fallback (:110), name match with `toUpper agentShortName` (:91).
- `sasha/src/Engine/ActionDiscovery/Instances.hs`: `DirectionalStimulusF` object instance (:116–180), gates ordered actor, object, scene.
- `sasha/src/Engine/ActionDiscovery/Protocol.hs`: `fetchAgentAction` agent table then shared table (:83–91); `fetchSceneAction` (:94).
- `sasha/src/Model/Core.hs`: `ActionManagement` (:155); `Scene` (:235); World `_sharedActionManagement` (:273).
- `SignalNetwork.hs`: `playerTickBlock` (:236) takes names from `acKnownPlayers` (:249); `resolveCommands` (:450) lexes at :468 and :474, calls `generateGbnf` at :495 and :498.
- `acKnownPlayers` (`App.hs:159`): written only at `SignalNetwork.hs:628`; read by `processJoinsPure` (:362), `processLeavesPure` (:332), `LoginLogoutSpec` :421, :452, :496, :512.
- Player names live in `credentials.player_name` (`migrations/build/000000-auth.sql:30`); read by `credentialsQuery` (`Authentication.hs:352`) and `bootstrapQuery` (`World.hs:150`).
- Player agent GID is `users.user_id` via `GID (unMid uid)` (`Authentication.hs:307`, `:318`; `World.hs:136`).
- DSL: `createDSAManagement`, `createAVTargetManagement` (`SashaLambdaDSL.hs`), `Builder.hs` interpret cases, `Reify.hs:53`. Look-at keys on lobby scene, player template, floor, ball (`1-lobby.dsl`, `2-floor.dsl`, `3-ball.dsl`). `1-get-drop.dsl` uses `sharedBehavior`.
- e2e: `LookAtPlayerSpec` (`look at googly` expects "Nobody called…"), `LookAtBallSpec`, `ParseFailureSpec`.

## Old-code precedent (/home/mlitchard/gitlab/sasha)
- `sasha-engine/src/ActionDiscovery/Percieve/Look.hs:29–47`:
  ```haskell
  manageImplicitStimulusProcess = runActionProtocol @ImplicitStimulusF
  manageDirectionalStimulusProcess verb phrase =
    runActionProtocol @DirectionalStimulusF (verb,phrase)
  ```
- `sasha-engine/src/ActionDiscovery/Protocol.hs:106–116` `fetchAgentAction`, agent's own table only:
  ```haskell
  agentActions <- (^. agentActionManagement) <$> getAgentM agentGID
  let gid = fromMaybe (error $ "Agent: " <> noGIDError @actionF)
              $ lookupActionGID @actionF input agentActions
  ```
- `sasha-engine/src/ActionDiscovery/Helpers.hs:52–60`:
  ```haskell
  fetchSceneActions = do
    agentGID <- getActingAgentGID
    scene <- getAgentSceneM
    let base = view sceneActionManagement scene
        overlays = view sceneAgentOverlays scene
    case Data.Map.Strict.lookup agentGID overlays of
      Nothing      -> pure base
      Just overlay -> pure (mergeOverlay overlay base)
  ```
- `sasha-engine/src/ActionDiscovery/Instances.hs:438–463` `ImplicitStimulusF`, player then scene:
  ```haskell
  case (playerAction, sceneAction) of
    (ImplicitNoStimulusF pf, _) -> pf playerKey
    (_, ImplicitNoStimulusF lf) -> lf sceneKey
    (ImplicitStimulusF ps, ImplicitStimulusF ls) -> ps playerKey >> ls sceneKey
  ```
- `sasha-engine/src/ActionDiscovery/Instances.hs:467–531` `DirectionalStimulusF`: `validateObjectLook nounPhrase` splits object/agent. Object path gates player, object, scene. Agent path gates the player only, then narrates `agentDescription`.
- `sasha-core/src/Model/Core.hs:1208–1218`:
  ```haskell
  data Scene = Scene
    { _title, _sceneDescription, _sceneIntroduction, _objectSemanticMap
    , _sceneObjects, _sceneActionManagement, _agentSemanticMap
    , _sceneAgents, _sceneAgentOverlays :: Map (GID Agent) ActionManagementFunctions }
  ```
- `sasha-grammar/src/Grammar/Parser/Lexer.hs:24–30`: `lexify` uppercases (`str' = toUpper txt`). Old code has no `classify`.

Ruled departures from old code: lowercase intake (ruling 11); gate order agent, scene, target (ruling 2); agent target gets its own gate (ruling 3); `throwMaybeM` in place of `error` (ruling 8); shared tables (ruling 9); `_agentSemanticMap` dropped (ruling 7).

Still to quote: `mergeOverlay` and `validateObjectLook` (imported in the old files). Steps 6 and 7 start by quoting them.

## Decisions
All decided — see Rulings. None open.

## Steps
Step rule: every step builds and is green on its own. Any fix a step needs — imports, exports, callers, instances, tests — lands in that step.

1. **Lowercase intake.** `resolveCommands` lowercases `GameCommand` and `RepairedCommand`. `lexify` drops `toUpper`; `classify` literals lowercase. `Gbnf.hs` `named` drops `toUpper`; grammar terminals lowercase. `Look.hs:91` compares without `toUpper`. `validate` lowercases account names. New migration in `migrations/build/` (existing naming) lowercases existing `credentials.player_name`. Lexer, parser and GBNF tests that use uppercase input or literals are updated.
2. **Schema.** New file `migrations/build/000006-player-name.sql`: `ALTER TABLE users ADD COLUMN player_name TEXT UNIQUE NOT NULL;` and `ALTER TABLE credentials DROP COLUMN player_name;`. In the same step every site that reads or writes `player_name` moves to `users`: `Authentication.hs` `authAvailable`, `credentialsQuery`, `insertUser`, `insertCredentials`; `World.hs` `mintBootstrapToken`; `FakeProvider.hs` `seedAccount`; `LoginLogoutSpec.hs` `insertExpired` and `:853`; `MigrationSpec.hs` `insertPlayer`.
3. **UNKNOWN and the player lookup.** `classify` catch-all becomes `UNKNOWN w`. The `playerTickBlock` gather phase collects UNKNOWN words, runs `selectPlayerWords` (one batched query, `status = 'active'`) giving `PlayerLookup`. Found words are promoted to `PLAYERNAME`; `PlayerLookupFailed` sends `playerLookupFailureText` to the player. `generateGbnf` names come from the lookup. `LookAtPlayerSpec` `googly` → `bootstrap`; `ParseFailureSpec` updated where UNKNOWN changes the path.
4. **Remove `acKnownPlayers`.** `processJoinsPure` decides new/returning by `agentMap` membership; `processLeavesPure` uses `user_id` with no live session. Remove the field, its write at :628, and update `LoginLogoutSpec`.
5. **Shared tables per kind.** Replace `_sharedActionManagement` with the three tables (ruling 9); DSL constructors, `Builder` cases, `Reify` entries. `1-get-drop.dsl` → `sharedAgentBehavior`. Get/drop gates: own table, shared table, `throwMaybeM`.
6. **Scene overlays.** Quote old `mergeOverlay` first. Add `_sceneAgentOverlays` to `Scene`; port `fetchSceneActions` to `Helpers.hs`, overlay merged over base.
7. **Target keys and look dispatch.** Quote old `validateObjectLook` first. Add `DSATargetManagementKey`, `ISATargetManagementKey`, the two lookups, the two DSL wrappers, `Builder`/`Reify` entries. Remove the scene's `DSAManagementKey`/`ISAManagementKey`. `Look.hs` becomes pure `runActionProtocol` delegation. `ImplicitStimulusF`: agent, scene (`ISATargetManagementKey`). `DirectionalStimulusF`: agent, scene, target (object, or agent found via `sceneAgents` + `agentShortName`). Each gate: own table, shared table, `throwMaybeM`. `1-lobby.dsl`, `2-floor.dsl`, `3-ball.dsl` move to target keys; player template target key gets its own GID. `LookAtPlayerSpec` and `LookAtBallSpec` green.
8. **Narrowed repair grammar.** `generateGbnf` narrows to `LOOK AT <player-name>` when the sentence holds a `PLAYERNAME` and no object words. `resolveCommands` passes the actor's verbs (own table, then shared agent table). Targets stay vocabulary-wide. A test asserts `show me raj` never yields `look at red ball`.
