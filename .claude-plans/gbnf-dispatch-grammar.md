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
13. The lookup runs in the IO gather phase of `playerTickBlock`, one batched query, `status = 'active'`. Its only job is to decide whether each `UNKNOWN` word is a player name for parsing and grammar repair; the player is never sent a message about it. Names: `PlayerLookup = PlayerWordsFound (Set PlayerName) | PlayerLookupFailed SqlError`, `selectPlayerWords`. On `PlayerLookupFailed` every word stays `UNKNOWN`, the command parses and repairs as usual, and the `SqlError` is written to stderr as at `SignalNetwork.hs:278`. RULED (user, 2026-10-19).
14. `users` is the one source for "is a player". `acKnownPlayers` is removed: grammar names come from `users`; joins decide new/returning by `agentMap` membership; a departure is a `users.user_id` with no live session.
15. Schema: `player_name` moves from `credentials` to `users` as `TEXT UNIQUE NOT NULL`. `credentials` takes no token column; `tokens.user_id` (UNIQUE, REFERENCES users) links a token to its account. RULED (user, 2026-10-19).
16. Account names are lowercased in `validate`; a migration lowercases existing names.
17. When the sentence holds a `PLAYERNAME` and none of the object words, `generateGbnf` narrows to `LOOK AT <player-name>`.
18. Repair-grammar verbs come from the actor's own table, then the shared agent table. Targets stay vocabulary-wide.
19. e2e `look at googly` becomes a name seeded but not in the scene, e.g. `bootstrap`.
20. Later: world agents need a GID source that cannot collide with `users.user_id`.
21. Step 2: the database is built fresh from `migrations/build/`. sashamud-d8 writes the next SQL file, `000006-player-name.sql`, and changes the code that reads `player_name` in the same step. RULED (user, 2026-10-19).
22. Step 1: sashamud-d8 writes the migration that lowercases existing `credentials.player_name` values.
23. The repair grammar is generated per sentence. When the sentence holds no matched player name, `generateGbnf` leaves out the `directional-stimulus-verb … player-name` alternative and the `player-name` rule. RULED (user, 2026-10-19).
24. Bots do not log in. Table `agents`: `agent_id SERIAL PRIMARY KEY`, `agent agent_kind NOT NULL` (enum mirroring Haskell `AgentKind`: `denizen`, `fixture`), `name TEXT UNIQUE NOT NULL`. A player's id is its agent id: `users.user_id INT PRIMARY KEY REFERENCES agents(agent_id)`. `users.player_name` is dropped; every agent's name lives in `agents.name`. Settles ruling 20. RULED (user, 2026-10-19).
25. `PLAYERNAME` is renamed `AGENTNAME`. RULED (user, 2026-10-19).
26. The name lookup is `SELECT agent_id, name FROM agents WHERE name = ANY (?)`, with no status filter and no `agentMap` filter. Every name found becomes `AGENTNAME`; a word missing from `agents` stays `UNKNOWN` and goes to repair. RULED (user, 2026-10-19).
27. Bots are agents and are tracked in `agentMap`. Joins decide new or returning by `agentMap` membership. A departure is an agent in `agentMap` with no `InGame` session. RULED (user, 2026-10-19).
28. Looking at an `AGENTNAME` whose agent is not in the looker's scene narrates "you don't see <AgentName> here", replacing "Nobody called…". RULED (user, 2026-10-19).
29. Looking at an agent in the looker's scene runs that agent's "looked at" action. RULED (user, 2026-10-19): "if their player is in the scene then the action associate with their 'looked at' action activates".
30. The standard "looked at" action narrates the target's `_agentDescription` to the looker. Any particular player can carry a different, arbitrary action through their own `DSATargetManagementKey`. RULED (user, 2026-10-19): "the standard action will access the _description but because we are doing this right it can be any arbitrary action we decide for particular players".
31. The target agent's own action table is checked first; when it has no "looked at" action, `_sharedActionManagement` is checked, and it holds the standard "looked at" action. Same order as `fetchAgentAction` (`Protocol.hs:83`). One standard action GID, one effect linked to it. RULED (user, 2026-10-19): "A"; "if someone is looked at, they check from there own map, if it doesn't exist then it should check a shared map for the standard looked at action".
32. The target's GID travels with the look to the "looked at" effect, the same way `AgentWitnessContext targetGid` carries it to witnesses (`processWitnesses`, `ActionManagement.hs:311`; `WitnessF wf -> wf witnessGid actorGid witnessCtx`). The effect reads the target from `world . agentMap` and its `agentDescription`. RULED (user, 2026-10-19): "yes do the same here".
33. The "looked at" action lands in step 4. Step 4 also removes the placeholder line `modifyAgentNarration actorGid (over actionConsequence (<> [view agentDescription target]))` from the `[targetGid]` branch of `manageAgentStimulusProcess` in Look.hs. RULED (user, 2026-10-19): "no looked at moves here to, there should be no placeholder code".
34. `EntityKey` comes into sashamud from the old code (`sasha-core/src/Model/Core.hs:929`) with its constructors as they are: `SceneKey' (GID Scene)`, `ObjectKey' (GID Object)`, `ActingAgentKey`, `AgentKey' (GID Agent)`, `SceneAgentKey (GID Scene)`. RULED (user, 2026-10-19): "i think it is EntityKey". Superseded by ruling 40.
35. Two newtypes wrap `EntityKey`: `ActorKey` (the entity doing the action) and `TargetKey` (the entity acted upon). Scenes, objects and agents can all act. RULED (user, 2026-10-19): "for Actor we use EntityKey as well this will let object and scenes actively act"; "ActorKey / TargetKey these will wrap an entityKey".
36. The map that tracks which action key maps to which action gets an outer map keyed by `ActorKey`, then `TargetKey`: `Map ActorKey (Map TargetKey (...))`. It applies to all actions; a plain look targets a scene. RULED (user, 2026-10-19): "the map that tracks what actionkey maps to what action needs wo have an outer map for the agent doing the looking … this needs to apply to all actions".
37. The standard "looked at" narration constructor is `LookAtAgentNarration`, with no argument. The target reaches it as a `TargetKey`; this is what carries the target GID in ruling 32. RULED (user, 2026-10-19): "LookAtAgentNarration".
38. A new sum type `data Entity = AgentEntity | ObjectEntity | SceneEntity` names the kind of entity. RULED (user, 2026-10-19): "okay change to AgentEnity ObjectEntity SceneEntity".
39. `_sharedActionManagement` takes the form `Map VerbKey (Map Entity ...)`, and `_sharedWitnessManagement` takes the same form, `Map VerbKey (Map Entity (GID WitnessF))`. The shared fallback is set per entity kind; this covers what step 6 planned. RULED (user, 2026-10-19): "_sharedActionManagement have the outer key be an action key and points to a new sum type data Entity = Object | Agent | Scene _SharedWitnessManagement similar form"; "yes VerbKey". Witness half superseded by ruling 46.
40. The existing sashamud type `EntityID` (`Model/Core.hs:253`, constructors `EntityObject` and `EntityAgent`) is renamed `EntityKey`, and a constructor `EntityScene` is added alongside `EntityObject` and `EntityAgent`, in the same form they take. `ActorKey` and `TargetKey` (ruling 35) wrap this `EntityKey`. Supersedes ruling 34. RULED (user, 2026-10-19): "EntityID needs to be changed to EntityKey and add EntityScene".
41. The effect registries are keyed per entity with `ActorKey` and `TargetKey` (ruling 35), at the same three levels as ruling 42, most specific first: (1) `Map ActorKey (Map TargetKey (Map ActionEffectKey (Set WorldOutcome)))` — this actor on this target; (2) effects for the target alone, any actor; (3) the shared default for the entity kind, keyed by `Entity`. The entity-action registry takes the same form. The standard "looked at" effect is filed once at level 3 and reads its target at run time (ruling 37); player-specific or pair-specific effects at levels 2 or 1 take priority over it. RULED (user, 2026-10-19): "the ActionEffectKey in the effect registries can be per entity key , not the same for everything everyone"; "there needs to be two new newtype wrappers for EntityKey to distinguish between target and actor"; "i accept the fix to ruling 41".

42. The action GID for a verb is looked up at three levels, most specific first: (1) `Map ActorKey (Map TargetKey ActionManagementFunctions)` — this actor acting on this target; (2) the target's own table on its entity record (`agentActionManagement` and the object and scene tables) — any actor; (3) `_sharedActionManagement :: Map VerbKey (Map Entity ...)` — the shared default for that kind of entity. `actionMaps` stays keyed by GID. RULED (user, 2026-10-19): "yes I also agree that … the one that picks which action GID runs for a verb … a lookup goes through three levels, most specific first".
43. Rulings 29-42 land in step 4 with the "looked at" action: the `EntityKey` rename with `EntityScene`, the `Entity` type, `ActorKey`/`TargetKey`, the three-level lookup, the reshaped shared tables and effect registries, and the action signature change with every caller. Steps 6 and 8 fold into step 4. RULED (user, 2026-10-19): "yes".
44. Narration from an action goes to a list of recipients relevant to that action. Most often, though not always, the list is the players in the scene where the action takes place. This settles where narration goes when the actor is a scene or an object (ruling 35). RULED (user, 2026-10-19): "the narration goes to whomever is in a list of those relevant. most of the time but not always it will be players in the scene where the action takes place".

45. `newtype AgentKey = AgentKey (GID Agent)`. `AgentWitnessMap :: Map AgentKey (Map EntityKey (GID WitnessF))` decides who receives an action's narration (ruling 44) and which witness action they get: when entity E acts, every agent with an entry for E gets that entry's `WitnessF`, called with the event's `WitnessContext`. Entries stay in place; a change of state (closing one's eyes) points the entry at a different `WitnessF`. The witness function tells events apart by the `WitnessContext` constructor (`AgentWitnessContext`, `FailedAgentLookContext`), so no `VerbKey` level is needed; a new kind of event gets its own `WitnessContext` constructor. The map is usually filled from the players in the scene, though not always. RULED (user, 2026-10-19): "there should be a new map AgentWitnessMap that has Map (AgentKey) (Map EntityKey) (Key to relevant action type)"; "if someone closes their eyes they should not be able to witness"; "you would not remove the entry just change what the key points to"; "does not WitnessF allow for different verbs already?"; "a new newtype over GID Agent".

46. The actor in `WitnessEffectF` is an `ActorKey` (wrapping `EntityKey`, ruling 35): `GID Agent -> ActorKey -> WitnessContext -> GameComputation Identity ()`. `VerbKey` is dropped from witness selection: the `agentWitnessManagement` field, the verb-keyed `WitnessBehavior` and `SharedWitnessBehavior` DSL constructors, and the `VerbKey` argument of `processWitnesses` go, with every caller. `_sharedWitnessManagement :: Map Entity (GID WitnessF)` is the shared default witness action keyed by the actor's entity kind, used when a witness has no `AgentWitnessMap` entry for that actor. Replaces the witness half of ruling 39. RULED (user, 2026-10-19): "Actors are now EntityKeys"; "yes we need a shared default WitnessF keyed by Entity, and drop VerbKey".

47. When an actor acts, the witnesses are: (1) every agent with an `AgentWitnessMap` entry for that actor, who gets that entry's `WitnessF`; (2) every other agent in the actor's scene (`sceneAgents`, excluding the actor) with no entry for that actor, who gets the shared default `_sharedWitnessManagement` for the actor's `Entity` kind. RULED (user, 2026-10-19): "that one" (choosing: the agents in the actor's scene who have no entry for that actor receive the shared default).

48. The existing `EntityKey` (`Model/Core.hs:348`, constructors `SceneKey'`, `ObjectKey'`, `ActingAgentKey`, `AgentKey'`) is removed. The new `EntityKey` (ruling 40: `EntityID` renamed, constructors `EntityObject`, `EntityAgent`, `EntityScene`) replaces it everywhere the old one is used: `EntityActionRegistry` (`Core.hs:433`), `lookupEntityActions` / `processPropActionEffects` / `processEntityActionEffect` (`Engine/Resolution/ActionManagement.hs:97-126`), `LinkEntityActionEffect` / `linkEntityActionEffect` (`DSL/Model/EDSL/SashaLambdaDSL.hs:106`, `:210`), the Reify name list (`DSL/Reify.hs:121`), and the export and import lists. `SceneKey'` → `EntityScene`, `ObjectKey'` → `EntityObject`, `AgentKey'` → `EntityAgent`. `ActingAgentKey` is dropped; the actor comes from the `ActorKey` the action receives (rulings 35, 41). Lands in step 4 (ruling 43). RULED (user, 2026-10-19): "this looks like a vestige that can be replaced with our current understanding of Entity and the concept of 'acted upon'"; "okay remove the old data EntityKey and replace with new".

49. RULED (user, 2026-10-19). Look narration is mapped to each player, keyed by `AgentKey`. When a look runs, each recipient's narration is filed under that recipient's `AgentKey`. Only players are sent narration, so the browser receives player narration only and applies no filter. `LookAtPlayerSpec` reads the narration filed under each player's `AgentKey` to tell the target's text from the looker's. Lands in step 4 (ruling 43).

50. RULED (user, 2026-10-20). `ActionEffectKeyF` becomes a newtype: `newtype ActionEffectKeyF = ActionEffectKeyF (ActorKey -> TargetKey -> ActionEffectKey -> GameComputation Identity ())`. It is unwrapped by pattern match at each call site, the way `processWitnesses` unwraps `WitnessF wf` (`ActionManagement.hs:334`). `lookAtF` becomes `DirectionalStimulusF (ActionEffectKeyF processActionOutcomeRegistry)` (`Actions.hs:31`). Every other action value, and every action call in `Instances.hs` and `Look.hs`, changes the same way. This is the action signature change in ruling 43. Lands in step 4. User: "i have consistently told you to use established patterns what makes you choose type over newtype"; "yes".

51. RULED (user, 2026-10-20). `_sharedActionManagement :: Map VerbKey (Map Entity ActionManagementFunctions)`. The DSL constructor is `SharedBehavior :: Entity -> ActionManagement -> SashaLambdaDSL ()`. The `Builder.hs` clause reads the `VerbKey` off the key by pattern match (`DSAManagementKey verb _` → `DirectionalStimulusKey verb`, `ISAManagementKey verb _` → `ImplicitStimulusKey verb`, `AVTargetManagementKey`/`AVSupportManagementKey verb _` → `AcquisitionKey verb`, `DVManagementKey`/`DVSurfaceManagementKey verb _` → `DivestmentKey verb`) and inserts the key into the set at that `VerbKey` and `Entity`. A `VerbKey` paired with the wrong kind of key cannot be written. The value stays a `Set` (`ActionManagementFunctions`), as in the old code, to prevent duplicates. Reads use the existing per-constructor lookups (`lookupActionGID`, `findAVSupportKey`, `findDVSurfaceKey`) on the set. Lands in step 4. User: "we cant allow this sharedBehavior (DirectionalStimulusKey dsaLook) AgentEntity isaLookKey"; "okay keep it … i chose set over list to prevent duplicates".

52. RULED (user, 2026-10-20). The level-1 action table from ruling 42 is a field of `World`: `_actorTargetActionManagement :: Map ActorKey (Map TargetKey ActionManagementFunctions)`, with lens `actorTargetActionManagement`. It sits next to `_sharedActionManagement`. Lands in step 4. User: "yes i want it in World"; "1".

53. RULED (user, 2026-10-20). The three registry levels from ruling 41 are fields of `PossibilityGraph`, replacing `_worldOutcomeEffects` and `_entityActionEffects`: `_actorTargetWorldOutcomeEffects :: Map ActorKey (Map TargetKey WorldOutcomeRegistry)`, `_targetWorldOutcomeEffects :: Map TargetKey WorldOutcomeRegistry`, `_sharedWorldOutcomeEffects :: Map Entity WorldOutcomeRegistry`, `_actorTargetEntityActionEffects :: Map ActorKey (Map TargetKey EntityActionRegistry)`, `_targetEntityActionEffects :: Map TargetKey EntityActionRegistry`, `_sharedEntityActionEffects :: Map Entity EntityActionRegistry`. Lookup takes the most specific level found, as ruling 41 says. Lands in step 4. User: "yes".

54. RULED (user, 2026-10-20). `AgentWitnessMap` (ruling 45) is metadata about the world, so it lives in `GameState` next to `_agentLocationMap`: `_agentWitnessMap :: Map AgentKey (Map EntityKey (GID WitnessF))`, with lens `agentWitnessMap`. Lands in step 4. User: "i think it's meta data about the world not something about the world itself".

55. RULED (user, 2026-10-20). `_agentWitnessMap` is filled at join, from the scene. In `joinComputation (NewPlayerJoined …)`, the new player gets an entry for each agent already in the scene (`EntityAgent g`). Each of those agents gets an entry for the new player (`EntityAgent gid`). Every entry points at the shared default `_sharedWitnessManagement` for `AgentEntity`. If that default is missing, it is a `throwError "Programmer Error: …"`, the same way the join already handles a missing template. `processWitnesses` reads these entries first (ruling 47). Lands in step 4. User: "fill it at join".

56. RULED (user, 2026-10-20). A departed player is in no recipient list. Departure (`processLeavesPure`) removes the leaver's own entry from `_agentWitnessMap` (`at (AgentKey gid) .~ Nothing`) in the same pass that removes them from `sceneAgents`. The entries other agents hold for the leaver stay. `ReturningPlayerJoined` refills the returner's entry from the scene they rejoin, as ruling 55 does for a new join, and adds an entry for the returner to each agent in that scene that has none. Every entry points at the shared default for `AgentEntity`. Keeping a departed player's own entries across a leave is save/load's job. Lands in step 4. User: "the Player that left should not be in the list of Players to be sent the narration in the first place".

57. RULED (user, 2026-10-20). `NarrationMap` is keyed by `AgentKey`: `newtype NarrationMap = NarrationMap { _unNarrationMap :: Map AgentKey Narration }`. The signature becomes `modifyAgentNarration :: AgentKey -> (Narration -> Narration) -> GameComputation Identity ()`, and every caller passes an `AgentKey`. An effect that narrates to its actor matches `ActorKey (EntityAgent g)` to get `AgentKey g`. A scene or object actor narrates through the recipient list (ruling 44). `announceToDenizens` files under `AgentKey g`. `extractNarration` and `composeTick` return `Map AgentKey Narration`. `deliverNarrationIO` takes that map and unwraps the key to match `sessionGid`. Lands in step 4. User: "yes AgentKey".

58. RULED (user, 2026-10-20). Narration goes only to players who can receive it. The recipient list decides this: the agent's `_agentWitnessMap` entry, or the shared default for an in-scene agent with no entry (rulings 45, 47). A player outside that list has nothing filed, which covers a departed player (ruling 56) and an entry pointing at a `WitnessF` that narrates nothing. `LookAtPlayerSpec` tells narrations apart by recipient `AgentKey`, and each socket carries only its own player's narration (ruling 49). In `lookAtPlayerTest` the looker's socket (raj) receives the description ("A player."). In `lookAtPlayerWitnessTest` the target's socket (sasha) receives the witness line ("looks at") and not the description. No wire change and no description change. Lands in step 4. User: "only agents get narrations this has nothing to do with target"; "narrations only go to players that can get the narration".

59. RULED (user, 2026-10-20). The shared witness default is set by `SharedWitnessBehavior :: Entity -> GID WitnessF -> SashaLambdaDSL ()`, which writes `world . sharedWitnessManagement . at entity ?~ witnessGid` (ruling 46). `WitnessBehavior` is removed, along with its `Builder.hs` clause and `Reify.hs` entry. In `1-lobby.dsl`, the two `witnessBehavior` calls and the `witnessGID` parameter of `playerTemplate` are removed, and one `sharedWitnessBehavior AgentEntity witnessGID` takes their place. In `1-get-drop.dsl`, the two verb-keyed `sharedWitnessBehavior` calls become one `sharedWitnessBehavior AgentEntity witnessGID`. Lands in step 4. User: "yes".

60. RULED (user, 2026-10-20). `WitnessEffectF` becomes a newtype: `newtype WitnessEffectF = WitnessEffectF (AgentKey -> ActorKey -> WitnessContext -> GameComputation Identity ())`. The witness argument is an `AgentKey`. `WitnessF` keeps wrapping it (`data WitnessF = WitnessF WitnessEffectF`), unwrapped by pattern match the same way as ruling 50. `witnessF` becomes `WitnessF (WitnessEffectF processWitnessEffects)` (`Actions.hs:49`). Replaces the type in ruling 46. Lands in step 4. User: "newtype".

61. RULED (user, 2026-10-20). The target-key lookups are `lookupDirectionalStimulusTarget` and `lookupImplicitStimulusTarget`. They follow `lookupDirectionalStimulus`/`lookupImplicitStimulus` and the old `findAVTargetKey`. The DSL wrappers are `CreateDSATargetManagement` and `CreateISATargetManagement` (lowercase `createDSATargetManagement`, `createISATargetManagement`). Their `Builder.hs` clauses return `DSATargetManagementKey verb gid` and `ISATargetManagementKey verb gid`, following `CreateDSAManagement`/`CreateISAManagement`. The existing `*Behavior` constructors insert the keys. Lands in step 4. User: "yes".

62. RULED (user, 2026-10-20). `ActionProtocol` gains `mkVerbKey :: ActionInput actionF -> VerbKey`, next to `mkEffectKey`. The instances are: `ImplicitStimulusKey` for implicit stimulus, `(verb, _) -> DirectionalStimulusKey verb` for directional stimulus, `SimpleAcquisitionVerbPhrase verb _ -> AcquisitionKey verb` for acquisition, and `SimpleDivestmentVerbPhrase verb _ -> DivestmentKey verb` for divestment. The level-3 lookup's `Entity` is read off the looked-up key's `EntityKey` by pattern match: `EntityAgent` gives `AgentEntity`, `EntityObject` gives `ObjectEntity`, `EntityScene` gives `SceneEntity`. Lands in step 4. User: "yes".

63. RULED (user, 2026-10-20). Each level of rulings 41, 52 and 53 has a writer. All land in step 4. "…" stands for the arguments the existing `Link*` constructor takes.
- World-outcome registry: `LinkWorldOutcomeEffect :: Entity -> …` writes `_sharedWorldOutcomeEffects`; `LinkTargetWorldOutcomeEffect :: TargetKey -> …` writes `_targetWorldOutcomeEffects`; `LinkActorTargetWorldOutcomeEffect :: ActorKey -> TargetKey -> …` writes `_actorTargetWorldOutcomeEffects`.
- Entity-action registry: `LinkEntityActionEffect :: Entity -> …` writes `_sharedEntityActionEffects`; `LinkTargetEntityActionEffect :: TargetKey -> …` writes `_targetEntityActionEffects`; `LinkActorTargetEntityActionEffect :: ActorKey -> TargetKey -> …` writes `_actorTargetEntityActionEffects`.
- Action tables: level 3 is `SharedBehavior` (ruling 51). Level 2 is the existing `*Behavior` constructors writing the target's own table (ruling 61). Level 1 is `ActorTargetBehavior :: ActorKey -> TargetKey -> ActionManagement -> SashaLambdaDSL ()`, which writes `world . actorTargetActionManagement`.
- Each new constructor gets a lowercase DSL function, a Builder clause and a Reify entry.

64. RULED (user, 2026-10-20). Every gate of an action receives the same `ActorKey` (the actor) and the same `TargetKey` (the entity acted upon; the scene for a bare look). The three-level target fetch is `fetchTargetAction` in `Protocol.hs`, beside `fetchAgentAction` and `fetchSceneAction`. It checks level 1 `actorTargetActionManagement`, then level 2 the target's own table, then level 3 `sharedActionManagement` at `mkVerbKey input` and the target's `Entity`, and it fails with `throwMaybeM` when none is found. `ActionProtocol` gains `lookupTargetActionGID` beside `lookupActionGID`. The instances are `lookupImplicitStimulusTarget` for implicit stimulus, `lookupDirectionalStimulusTarget` for directional stimulus, `findAVKey` for acquisition and `findDVKey` for divestment. A scene actor's scene is that scene. An object actor's scene is the scene whose `_sceneObjects` holds it. The floor, ball, get-drop-ball and lobby scene-look links are filed at level 2 under the `TargetKey` of that object or scene. The standard looked-at effect is filed at level 3 under `AgentEntity`. Lands in step 4. User: "of course the answer is yes"; "yes".

65. RULED (user, 2026-10-20). `PlayerName` is incorporated into `NounPhrase`. A named agent reaches the `DirectionalStimulusF` instance through its existing `(DirectionalStimulusVerb, DirectionalStimulusNounPhrase)` input, and `Look.hs` becomes pure `runActionProtocol` delegation (old step 8). Lands in step 4. User: "the PlayerName needs to be incorporated into NounPhrase".

66. RULED (user, 2026-10-20). A player name is the head noun of its own phrase: `newtype PlayerNamePhrase = PlayerNamePhrase (NounPhrase PlayerName)` in `Nouns.hs`, following the old code's per-noun phrase newtypes (`ObjectPhrase`, `PortalPhrase`, `ConsumableNounPhrase`, `SomaticStimulusNounPhrase`). sashamud adds the old code's other phrase newtypes as the features that use them arrive. `DirectionalStimulusNounPhrase` gains a second constructor, `PlayerDirectionalStimulusNounPhrase DirectionalStimulusMarker PlayerNamePhrase`. The look rule builds it from the marker and `nounPhraseRule` with `playerNameRule` as the noun rule, so determiners and adjectives compose with a name the same way they do with any noun. This replaces `AgentStimulusVerbPhrase`, its clause in `evalStimulusVerbPhrase` and `manageAgentStimulusProcess`. `PlayerName` gains `FromJSON` and `ToJSON` to meet `NounPhrase`'s deriving. `PlayerNamePhrase` derives the same set as `DirectionalStimulusNounPhrase`. `ArbitraryOrphans.hs` gains `Arbitrary` instances for `PlayerName` and `PlayerNamePhrase`. Lands in step 4. User: "do you see how we're going to need a new newtype?"; "sashamud will use the rest as we add them"; "yes to both".

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

Still to quote: `mergeOverlay` and `validateObjectLook` (imported in the old files). Steps 7 and 8 start by quoting them.

## Decisions
All decided — see Rulings. None open.

## Steps
Step rule: every step builds and is green on its own. Any fix a step needs — imports, exports, callers, instances, tests — lands in that step.

1. **Lowercase intake.** `resolveCommands` lowercases `GameCommand` and `RepairedCommand`. `lexify` drops `toUpper`; `classify` literals lowercase. `Gbnf.hs` `named` drops `toUpper`; grammar terminals lowercase. `Look.hs:91` compares without `toUpper`. `validate` lowercases account names. New migration in `migrations/build/` (existing naming) lowercases existing `credentials.player_name`. Lexer, parser and GBNF tests that use uppercase input or literals are updated.
2. **Schema.** New file `migrations/build/000006-player-name.sql`: `ALTER TABLE users ADD COLUMN player_name TEXT UNIQUE NOT NULL;` and `ALTER TABLE credentials DROP COLUMN player_name;`. In the same step every site that reads or writes `player_name` moves to `users`: `Authentication.hs` `authAvailable`, `credentialsQuery`, `insertUser`, `insertCredentials`; `World.hs` `mintBootstrapToken`; `FakeProvider.hs` `seedAccount`; `LoginLogoutSpec.hs` `insertExpired` and `:853`; `MigrationSpec.hs` `insertPlayer`.
3. **UNKNOWN and the player lookup.** `classify` catch-all becomes `UNKNOWN w`. The `playerTickBlock` gather phase collects UNKNOWN words, runs `selectPlayerWords` (one batched query, `status = 'active'`) giving `PlayerLookup`. Found words are promoted to `PLAYERNAME`; on `PlayerLookupFailed` the words stay `UNKNOWN` and the `SqlError` goes to stderr (ruling 13). With no matched player, the grammar leaves out the player branch (ruling 23). `generateGbnf` names come from the lookup. `LookAtPlayerSpec` `googly` → `bootstrap`; `ParseFailureSpec` updated where UNKNOWN changes the path.
4. **Agents, entity keys, three-level lookup, witnesses, look dispatch (rulings 24-66).**
   - **4a. Agents table, AGENTNAME, name lookup, failure narration (rulings 24-28).** On disk: the migration and rollback, `insertUser`, `seedAccount`, `createAccountSql`, the readers, the `AGENTNAME` lexeme, `selectPlayerWords`. Step 4's green covers it.
   - **4b. Core types (`Model/Core.hs`).** `EntityID` renamed `EntityKey` with `EntityScene (GID Scene)`; the old `EntityKey` removed (rulings 40, 48). New `ActorKey`, `TargetKey`, `AgentKey`, `data Entity` (rulings 35, 38, 45), same deriving as `EntityID`. `ActionManagement` gains `DSATargetManagementKey` and `ISATargetManagementKey`. `Agent` drops `_agentWitnessManagement` (ruling 46). `World`: `_sharedActionManagement :: Map VerbKey (Map Entity ActionManagementFunctions)` (ruling 51), `_sharedWitnessManagement :: Map Entity (GID WitnessF)` (ruling 46), `_actorTargetActionManagement` (ruling 52); the `NFData World` pattern and `defaultWorld` change with them. `GameState`: `NarrationMap` keyed by `AgentKey` (ruling 57), `_agentWitnessMap` (ruling 54). `PossibilityGraph`: the six registry fields (ruling 53); `defaultGameState` changes with them. `ActionEffectKeyF` and `WitnessEffectF` newtypes (rulings 50, 60). `NarrationComputation` gains `LookAtAgentNarration` (ruling 37).
   - **4c. Grammar (`sasha-grammar`).** `Nouns.hs`: `PlayerNamePhrase`, the second `DirectionalStimulusNounPhrase` constructor, `PlayerName` gains `FromJSON`/`ToJSON` (ruling 66). `Rules.hs`: the look rule builds `PlayerDirectionalStimulusNounPhrase` through `nounPhraseRule` with `playerNameRule` as the noun rule; the `AgentStimulusVerbPhrase` alternative goes. `Model.hs`: `AgentStimulusVerbPhrase` removed.
   - **4d. DSL (`SashaLambdaDSL.hs`, `Builder.hs`, `Reify.hs`).** `SharedBehavior :: Entity -> ActionManagement` with the VerbKey read off the key, target keys included (ruling 51). `SharedWitnessBehavior :: Entity -> GID WitnessF`; `WitnessBehavior` removed (ruling 59). `CreateDSATargetManagement`, `CreateISATargetManagement` (ruling 61). The `Link*` set with `Entity` on the existing two, and `ActorTargetBehavior` (ruling 63). Six `bs*` registry fields replace `bsWorldOutcomeRegistry` and `bsEntityActionRegistry` (Builder `:106-107,:157-158,:329-335,:391-392`). Reify: each new name in, `witnessBehavior` out.
   - **4e. Engine.** `Protocol.hs`: `mkVerbKey` (ruling 62), `lookupTargetActionGID`, `fetchTargetAction` levels 1→2→3 (ruling 64); `fetchAgentAction`'s shared lookup at `(mkVerbKey input, AgentEntity)`; `fetchSceneAction` reads the scene table with `lookupTargetActionGID`. `ActionManagement.hs`: `lookupDirectionalStimulusTarget`, `lookupImplicitStimulusTarget`; `processActionOutcomeRegistry :: ActorKey -> TargetKey -> ActionEffectKey` with the most specific registry level; `processEntityActionEffect` on the new `EntityKey`; `LookAtAgentNarration` narrates the target's `agentDescription` to the actor; non-agent actors narrate to the recipient list, with the scene from ruling 64; `processWitnesses :: ActorKey -> WitnessContext` per ruling 47; `processWitnessEffects` per ruling 60. `Instances.hs`: implicit look runs actor gate then scene as target (`EntityScene`). Directional look runs actor, target and scene gates, all with the same `ActorKey` and `TargetKey` (ruling 64). `PlayerDirectionalStimulusNounPhrase` finds the agent via `sceneAgents` and `agentShortName`: none narrates "you don't see X here" and runs `FailedAgentLookContext` witnesses; several narrate "Which X?"; one runs the gates, then the `AgentWitnessContext` witnesses. `DirectionalStimulusNounPhrase` keeps the object path. `extractDirectionalNoun` and `matchesAdjective` gain the new constructor. Get/drop pass `ActorKey (EntityAgent actorGid)` and `TargetKey (EntityObject objectGID)`. `Look.hs`: pure `runActionProtocol` delegation; `manageAgentStimulusProcess` and the placeholder line go (rulings 33, 65). `General.hs`: the `AgentStimulusVerbPhrase` clause goes. `Perception.hs`: `modifyAgentNarration` takes `AgentKey`, with its callers in Instances, ActionManagement and the witness effects. `Actions.hs`: all eight action values and `witnessF` use the newtypes.
   - **4f. Tick (`SignalNetwork.hs`).** Join fill (ruling 55); return refill and leave removal (ruling 56). `announceToDenizens`, `extractNarration`, `composeTick`, `deliverNarrationIO` on `AgentKey` (ruling 57).
   - **4g. World files.** `1-get-drop.dsl`: `sharedBehavior AgentEntity` for get and drop; one `sharedWitnessBehavior AgentEntity witnessGID`. `1-lobby.dsl`: witness field, witness parameter and both `witnessBehavior` calls go; `sharedWitnessBehavior AgentEntity witnessGID`; the scene's look keys become `createISATargetManagement`/`createDSATargetManagement`; the standard looked-at action is declared, `sharedBehavior AgentEntity`, linked by `linkWorldOutcomeEffect AgentEntity … LookAtAgentNarration`; the scene-look link moves to `linkTargetWorldOutcomeEffect (TargetKey (EntityScene lobbyGID))`. `2-floor.dsl`, `3-ball.dsl`: `createDSATargetManagement`, links at level 2 under the object's `TargetKey`. `4-get-drop-ball.dsl`: both links at level 2 under the ball's `TargetKey`.
   - **4h. Tests.** `SignalNetworkSpec` drops the witness field. `ArbitraryOrphans` gains `Arbitrary` for `PlayerName` and `PlayerNamePhrase`. `lookAtPlayerWitnessTest` fails if sasha's socket receives "A player." (ruling 58). Green: `LookAtPlayerSpec`, `LookAtBallSpec`, `LoginLogoutSpec`, `MigrationSpec`, `JSONSpec`, the Gbnf and parser tests.
5. **Remove `acKnownPlayers`.** `processJoinsPure` decides new/returning by `agentMap` membership; `processLeavesPure` uses `user_id` with no live session. Remove the field, its write at :628, and update `LoginLogoutSpec`.
6. **Shared tables per kind.** Folded into step 4 (ruling 43). Replace `_sharedActionManagement` with the three tables (ruling 9); DSL constructors, `Builder` cases, `Reify` entries. `1-get-drop.dsl` → `sharedAgentBehavior`. Get/drop gates: own table, shared table, `throwMaybeM`.
7. **Scene overlays.** Folded into step 4 (RULED user, 2026-10-20). `_sceneAgentOverlays` was never added to sashamud; nothing to write.
8. **Target keys and look dispatch.** Folded into step 4 (ruling 43). Quote old `validateObjectLook` first. Add `DSATargetManagementKey`, `ISATargetManagementKey`, the two lookups, the two DSL wrappers, `Builder`/`Reify` entries. Remove the scene's `DSAManagementKey`/`ISAManagementKey`. `Look.hs` becomes pure `runActionProtocol` delegation. `ImplicitStimulusF`: agent, scene (`ISATargetManagementKey`). `DirectionalStimulusF`: agent, scene, target (object, or agent found via `sceneAgents` + `agentShortName`). Each gate: own table, shared table, `throwMaybeM`. `1-lobby.dsl`, `2-floor.dsl`, `3-ball.dsl` move to target keys; player template target key gets its own GID. `LookAtPlayerSpec` and `LookAtBallSpec` green.
9. **Narrowed repair grammar.** `generateGbnf :: UnparsedSentence -> [PlayerName] -> [VerbKey] -> Gbnf` (RULED user, 2026-10-20). The verb list is the actor's own `_agentActionManagement` actor keys; for each verb kind the actor lacks, the shared agent table's `AgentEntity` entries fill it (RULED). Actor keys: `ISAManagementKey` → `ImplicitStimulusKey`, `DSAManagementKey` → `ImperativeKey`, `AVTargetManagementKey` → `AcquisitionKey`, `DVManagementKey` → `DivestmentKey`. `ISATargetManagementKey`, `DSATargetManagementKey`, `AVSupportManagementKey` and `DVSurfaceManagementKey` are scene, target and object gates and stay out (RULED). The actor is in `agentMap` by construction; the lookup throws on a miss (RULED). When the sentence holds an `AGENTNAME` and no object words (directional stimuli, objectives, adjectives, determiners), the grammar is `root ::= directional-look` and `directional-look ::= directional-verb " " agent-name`, with the actor's directional verbs and the named player (RULED). `resolveCommands` takes `view world gs`; the caller at `SignalNetwork.hs:293` changes in the same step. The four existing verb-list tests pass VerbKeys built from the vocabulary lists. `Gbnf.hs:66` gains the space after `::=` (RULED). Targets stay vocabulary-wide. A test asserts `show me raj` never yields `look at red ball`.

## Step 10: one writer for GameState

### Goal
GameState has one writer. dslTickSF and playerTickBlock stop looking and
adding. A writer on its own clock is the only caller of lookGameState and
addGameState. A failed player tick adopts nothing and tells the player in
the main view. A failed DSL write ends the process through journald.

### The fault
dslTickSF (DSLTick, 5 s) and playerTickBlock (PlayerTick, 1 s) each look
and add on separate clocks. monad-schedule resumes a branch with the
state it started with (AccumT . const). The last add wins and the other
branch's work is lost.

### Rulings
- RULED (user, 2026-10-21): one writer signal function on a WriterTick
  clock of 100 ms, inside RhineM, the sole looker and adder.
- RULED (user, 2026-10-21): one TChan, acWriteChan :: TChan Sender, with
  the writer as its only reader. dslTickSF and playerTickBlock send
  Sender values and never look or add.
- RULED (user, 2026-10-21): two answer slots in AppCtx, one per sender:
  acDslAnswer :: TMVar (WriteAnswer DslResult) and
  acPlayerAnswer :: TMVar (WriteAnswer PlayerResult). The writer puts
  into the slot for the sender it served. A sender takes from its own
  slot after sending.
- RULED (user, 2026-10-21): WriteAnswer a = Proceed a | TryAgain Text.
- RULED (user, 2026-10-21): Try = TryOne | TryTwo | TryThree | TryFailed,
  carried in the request. The writer reads it on every request. A sender
  sends TryOne; on TryAgain it sends TryTwo, then TryThree, then one
  TryFailed request so the writer takes the failure action. After that
  the sender carries on with its ticks.
- RULED (user, 2026-10-21): on DslSender TryFailed the writer sends the
  error to journald with priority Emergency and ends the process. No
  world means no mud. Anything that causes a shutdown is Emergency.
- RULED (user, 2026-10-21): on PlayerSender TryFailed the writer sends
  the player whose command failed a SystemMessage and a GameNarration
  with the error text in actionConsequence, so the message appears in
  the main view, and writes a log line. The request carries the Agent
  GID. The writer finds the session by GID through acSessions, as
  deliverNarrationIO does.
- RULED (user, 2026-10-21): the error carries the GID. GameComputation's
  ExceptT Text becomes ExceptT GameError. GameError has a constructor
  ActorError (GID Agent) GameError. runEvalFor and joinComputation catch
  with catchError and rethrow wrapped in ActorError. The computation
  fails, so the writer adopts nothing.
- RULED (user, 2026-10-21): the old code's catch (TopLevel.hs:157)
  narrates the error and keeps the partial state. That is the broken
  part. sashamud rethrows.
- RULED (user, 2026-10-21): login gate. acLoginGate :: TMVar
  ScriptMessage with ScriptMessage = WorldReady. A sigUSR1 handler puts
  WorldReady. authCallback reads the gate before the OIDC exchange and
  answers err500 while it is empty. Scripts and VM tests send sigUSR1
  after the last preliminary step. In-process harnesses use raiseSignal.
  No polling anywhere.
- RULED (user, 2026-10-21): the in-process harnesses (SeleniumHarness
  withServer, LoginLogoutSpec withTestServer) log the wizard in through
  mintBootstrapToken, the production path, post the world, log out, then
  raiseSignal sigUSR1.
- RULED (user, 2026-10-21): the in-process harnesses install the same
  sigUSR1 handler startServer installs, right after newAppCtx, so the
  raise lands in the test process. run-end-to-end's VM script has no
  logout step; the USR1 line after logout applies to run-deploy-tests.
  Both VM tests set SASHA_PID_FILE.
- RULED (user, 2026-10-21): the server writes its pid at startup to a
  pid file. Let binding pidFile = "sasha-server.pid"; env override
  SASHA_PID_FILE. Same shape as the bootstrap token file.
- RULED (user, 2026-10-21): the writer types live in Server.App.
  BuilderCounters, PInt, succPInt, unPInt, firstGID, initialCounters
  and the seven counter lenses move to Model.Core so DSL.Builder stops
  importing Server.App.
- RULED (user, 2026-10-21): the libsystemd C dependency in nix is
  sashamud-9b's task. This plan adds the Haskell dependency and the call.
- RULED (user, 2026-10-21): the journald priority is the Emergency
  constructor of hsyslog's Priority type, per the hsyslog documentation
  the user supplied.
- RULED (user, 2026-10-21): PlayerResult carries what playerTickBlock's
  IO needs after Proceed: playerResultNarrations,
  playerResultRepairReplies, playerResultJoins :: [JoinResult], and
  playerResultState :: GameState. JoinResult and its constructors
  NewPlayerJoined and ReturningPlayerJoined move from SignalNetwork.hs to
  Server.App. After Proceed, playerTickBlock runs executeJoinIO over
  playerResultJoins and builds the repair rows and the State views from
  playerResultState, as the current code does from gs'.
- RULED (user, 2026-10-21): the writer's per-request step is
  serveSender :: GameState -> Sender -> ServeResult in SignalNetwork.hs,
  exported for the tests. Served and ServeResult live in Server.App
  beside Sender. writerSF folds serveSender over the drained senders.
- RULED (user, 2026-10-21): no naked products, ever. A function that
  returns several values returns a record with named fields.
- RULED (user, 2026-10-21): on a failed player tick the SystemMessage
  carries gameErrorText err, the same text as the narration.
- RULED (user, 2026-10-21): the Sender functions return the result records
  alone. DslResult gains dslResultState :: GameState. DslSender carries
  GameState -> Either WorldBuilderError DslResult and PlayerSender carries
  GameState -> Either GameError PlayerResult. serveSender takes the new
  state from the result record on Right.
- Pinned: mailing errors to Michael.

### What exists today
- RhineM = AccumT (Last GameState) (ReaderT AppCtx IO)
  (SignalNetwork.hs:206). Pipeline at :236.
- dslTickSF :253-273. playerTickBlock :275-359, runPureComputation at
  :306, Left branch prints "Tick computation failed" to stderr at :340,
  addGameState gs' unconditionally at :359. composeTick :361.
  runEvalFor :502. lookupEvaluatorOrThrow :507. runPureComputation :514.
  drainChan :790 (tryReadTChan loop). deliverNarrationIO :780 filters
  acSessions by sessionGid and writes Routed sid (GameNarration narr) to
  acOutbound. executeJoinIO :758.
- Clocks.hs: HeartbeatTick = Millisecond 5000, PlayerTick = Millisecond
  1000, DSLTick = Millisecond 5000, with `type X :: Type` kind
  signatures.
- Server/App.hs: AppCtx :153-167, newAppCtx :169-194 (newTChanIO,
  newMVar, newIORef). sessionGid :122, sessionSend :127. BuilderCounters
  :90 with seven PInt fields.
- Server/Server.hs: deliverOutbound :133. startServer env reads :174;
  the SASHA_BOOTSTRAP_WIZARD failure at :178 prints to stderr and calls
  exitFailure (import System.Exit (exitFailure) at :95).
- Server/World.hs mintBootstrapToken :106 writes the token file with
  Data.Text.IO.writeFile.
- Server/Authentication.hs authCallback :270; the OIDC exchange begins
  at the parseRequest for /application/o/token/.
- Model/Core.hs: GameStateT :483, GameComputation :499 derives
  MonadError Text. Error.hs:8 throwMaybeM :: MonadError Text m => Text
  -> Maybe a -> m a.
- DSL/Builder.hs imports Server.App for BuilderCounters, the counter
  lenses, succPInt, unPInt (:93-104). Server/Log.hs imports DSL.Builder
  and Server.App (:8-11).
- Grammar: lexify (Lexer.hs:107) and parseTokens (Sentence.hs:20) return
  Either Text.
- Harnesses: sashamud-server/test-e2e/SeleniumHarness.hs withServer :129
  and sashamud-server/test/Integration/LoginLogoutSpec.hs withTestServer
  :225 log the wizard in with loginThroughFake (fake-oidc
  FakeProvider.hs:178), which lands in authCallback. LoginLogoutSpec
  :831 already runs mintBootstrapToken in-process with
  runHandler (runReaderT (unAppM (mintBootstrapToken name tokenPath)) ctx),
  reads the token file, posts DSL with it and logs out.
- Throw sites in GameComputation: SignalNetwork.hs composeTick :361,
  joinComputation :421-460, lookupEvaluatorOrThrow :507,
  commandComputation and actorVerbs :586-609; ActionManagement.hs
  modifySceneM/modifyObjectM/modifyAgentM :186-202, processWorldOutcome
  :205, processSpatialRelationshipEffect :213, processNarrationEffect
  :284-355, processWitnesses :358, processWitnessEffects :389-438;
  Perception.hs youSeeM :51; Instances.hs runActionProtocol instances
  :113, :150, :264, handleAcquisition :296, DivestmentF :364,
  objectMatchesAdjective :456; Protocol.hs fetchAction :85,
  fetchAgentAction :93, fetchSceneAction :109, fetchTargetAction :124.

### Sanctioned sources
- stm 2.5.3.1 (/home/mlitchard/github/stm): TMVar.hs newEmptyTMVarIO
  :80, takeTMVar :89 (retries on empty), putTMVar :110 (retries on
  full), tryReadTMVar. TChan.hs newTChanIO :70, writeTChan :117,
  readTChan :125, tryReadTChan :136.
- unix 2.8.8.0 (/home/mlitchard/github/unix): Signals.hsc sigUSR1 :211,
  installHandler :480 with Catch (IO ()), raiseSignal :409.
  Process/Common.hsc:104 getProcessID :: IO ProcessID, exported from
  System.Posix.Process (Process.hsc:29).
- rhine checkout: Millisecond.hs:31-49, Realtime.hs waitUTC :62-76. A
  late tick sleeps zero and fires at once with a lag tag. A long writer
  tick delays the next one; nothing is skipped and nothing runs
  concurrently with it.
- libsystemd-journal 1.4.6.0 (/home/mlitchard/github/libsystemd-journal):
  Systemd.Journal sendMessageWith :: Text -> JournalFields -> IO ()
  (Journal.hsc:166-193), priority :: Syslog.Priority -> JournalFields,
  JournalFields is a Monoid. pkgconfig-depends libsystemd >= 209.
- hsyslog Priority, from the documentation the user supplied: data
  Priority with constructors Emergency, Alert, Critical, Error, Warning,
  Notice, Info, Debug, in module System.Posix.Syslog.
- Old code: TopLevel.hs:157 `eval input `catchError` \err -> ...`,
  import Control.Monad.Error.Class (catchError) at :22. Old
  GameComputation threw Text and had no error sum type. sashamud's
  JoinFailure and WorldBuilderError are the sum type precedent.

### Types
In Model.Core, beside GameComputation:

    type GameError :: Type
    data GameError
      = ActorError (GID Agent) GameError
      | AgentMissing (GID Agent)
      | AgentLocationMissing (GID Agent)
      | SceneMissing (GID Scene)
      | ObjectMissing (GID Object)
      | WitnessFunctionMissing (GID WitnessF)
      | SpatialRelationshipsMissing (GID Object)
      | SupportMissing (GID Object)
      | ObjectActionMissing (GID Object)
      | ActionMissing Text
      | ActionGIDMissing Text
      | NoFloorHere (GID Scene)
      | SharedWitnessMissing
      | NewUserStartSceneMissing
      | NewUserTemplateMissing
      | EvaluatorMissing (GID Agent)
      | SessionMissing SessionId
      | ActorNotAgent ActorKey
      | TargetNotAgent TargetKey
      | ObjectInScene (GID Scene)
      | ParseFailed Text
      deriving stock (Eq, Generic, Show)

    gameErrorText :: GameError -> Text

RULED (user, 2026-10-21): gameErrorText renders one text per
constructor, the payload shown after it with pack (show _):
AgentMissing "Agent not found: ", AgentLocationMissing "Agent location
not found: ", SceneMissing "Scene not found: ", ObjectMissing "Object
not found: ", ObjectActionMissing "Object has no action: ",
ActorNotAgent "Programmer Error: non-agent actor: ", ObjectInScene
"Programmer Error: object in a scene: ", SessionMissing "Programmer
Error: no InGame session for ", NoFloorHere "There's nowhere to drop
that here." with no payload shown. Each remaining constructor keeps
the single text its site throws today with the payload appended.
ActorError gid err renders gameErrorText err. ParseFailed t renders t.
processNarrationEffect has no SupportMissing site; that source maps to
nothing. No test matches a Left from runPureComputation.

Constructor sources: AgentMissing, AgentLocationMissing, SceneMissing,
ObjectMissing are the "not found" lookups (target, support, spatial ref
and floor misses are ObjectMissing or AgentMissing by the GID's type).
WitnessFunctionMissing: processWitnesses. SpatialRelationshipsMissing,
SupportMissing: handleAcquisition and processNarrationEffect.
ObjectActionMissing: the four "has no acquisition/divestment action"
sites. ActionMissing: fetchAction's noActionError. ActionGIDMissing: the
"Agent: ", "Scene: ", "Target: " noGIDError sites in Protocol.hs.
NoFloorHere: "There's nowhere to drop that here." SharedWitnessMissing,
NewUserStartSceneMissing, NewUserTemplateMissing: joinComputation.
EvaluatorMissing: lookupEvaluatorOrThrow. SessionMissing:
commandComputation and actorVerbs. ActorNotAgent, TargetNotAgent: the
"non-agent actor" and "target is not an agent" branches. ObjectInScene:
"supported by a scene" and "contained in a scene". ParseFailed:
composeTick's auto-look parse; its payload becomes a grammar sum type in
the approved grammar-error cut, a separate commit.

In Server.App:

    type Try :: Type
    data Try = TryOne | TryTwo | TryThree | TryFailed
      deriving stock (Eq, Generic, Ord, Show)

    type WriteAnswer :: Type -> Type
    data WriteAnswer a = Proceed a | TryAgain Text
      deriving stock (Eq, Generic, Ord, Show)

    type DslResult :: Type
    data DslResult = DslResult
      { dslResultState    :: GameState
      , dslResultCounters :: BuilderCounters
      , dslResultReports  :: [Routed (Either WorldBuilderError [WorldChange])]
      }

    type PlayerResult :: Type
    data PlayerResult = PlayerResult
      { playerResultNarrations    :: Map AgentKey Narration
      , playerResultRepairReplies :: [Routed MessageFrom]
      , playerResultJoins         :: [JoinResult]
      , playerResultState         :: GameState
      }

    type Sender :: Type
    data Sender = DslSender Try (GameState -> Either WorldBuilderError DslResult)
                | PlayerSender Try (GameState -> Either GameError PlayerResult)

    data Served = DslServed Try (Either WorldBuilderError DslResult)
                | PlayerServed Try (Either GameError PlayerResult)

    data ServeResult = ServeResult
      { serveResultState  :: GameState
      , serveResultServed :: Served
      }

    type ScriptMessage :: Type
    data ScriptMessage = WorldReady
      deriving stock (Eq, Generic, Ord, Show)

AppCtx gains, after acDSLChan: acWriteChan :: TChan Sender,
acDslAnswer :: TMVar (WriteAnswer DslResult),
acPlayerAnswer :: TMVar (WriteAnswer PlayerResult),
acLoginGate :: TMVar ScriptMessage. newAppCtx makes them with newTChanIO
and newEmptyTMVarIO.

Clocks.hs gains `type WriterTick :: Type` and
`type WriterTick = Millisecond 100`.

Server.Log LogEntry gains TickFailed GameError, rendered with
gameErrorText.

### Steps
Step rule: every step builds and is green on its own. Any fix a step
needs, including imports, exports, callers, instances and tests, lands
in that step.

10.1 Move the counters. BuilderCounters, PInt, succPInt, unPInt,
firstGID, initialCounters and the seven counter lenses move from
Server.App to Model.Core unchanged. Every importer (DSL.Builder,
Server.Log, SignalNetwork, World, Server, tests) imports them from
Model.Core. Server.App imports what it still uses from Model.Core.

10.2 GameError. Add GameError and gameErrorText to Model.Core.
GameComputation derives MonadError GameError. throwMaybeM in Error.hs
takes a GameError. Every throw site listed above throws its constructor.
runEvalFor wraps the evaluator call with catchError and rethrows
ActorError gid err; joinComputation wraps each join the same way.
composeTick's Left err becomes throwError (ParseFailed err).
runPureComputation returns Either GameError a. playerTickBlock's Left
branch prints gameErrorText err. Imports: Control.Monad.Error.Class
(catchError) as in old TopLevel.hs:22. Tests that match on a Left Text
match the constructor.

10.3 Pid file and login gate. Server.hs startServer: let binding
pidFile = "sasha-server.pid", env override SASHA_PID_FILE read beside
the other env reads at :174; after the AppCtx exists, getProcessID and
Data.Text.IO.writeFile the pid, the mintBootstrapToken file pattern.
AppCtx gains acLoginGate, newAppCtx makes it with newEmptyTMVarIO.
startServer calls installHandler sigUSR1 (Catch (atomically (putTMVar
(acLoginGate ctx) WorldReady))) Nothing. authCallback calls
tryReadTMVar on the gate before the OIDC exchange and answers err500
while it is Nothing. start-sashamud sends `kill -USR1 "$(cat
"$pidFile")"` after the logout step; stop-sashamud removes the pid file
with the token file; flake.nix let binding pidFile; VM tests set
SASHA_PID_FILE under the state directory and send USR1 after their
logout. SeleniumHarness withServer and LoginLogoutSpec withTestServer
replace loginThroughFake for the wizard with the mint path of
LoginLogoutSpec :831: seedAccount, mintBootstrapToken through
runHandler and runReaderT over AppM into a temp token file, read the
token, post the world files with it, log out, then raiseSignal sigUSR1.
All of this is one step so every login path stays green.

10.4 The writer. Server.App gains Try, WriteAnswer, DslResult,
PlayerResult, Sender, Served, ServeResult, and JoinResult with
NewPlayerJoined and ReturningPlayerJoined moved from SignalNetwork.hs,
and AppCtx gains acWriteChan, acDslAnswer, acPlayerAnswer. Clocks.hs
gains WriterTick. SignalNetwork gains serveSender :: GameState ->
Sender -> ServeResult, exported for the tests, and writerSF :: ClSF
RhineM (IOClock RhineM WriterTick) () (), composed into the pipeline
with |@|. serveSender runs the sender's function on the state: on Right
result it returns ServeResult with the state taken from the result
record, dslResultState or playerResultState, and DslServed try (Right
result) or PlayerServed try (Right result); on Left err it returns the
state it was given with DslServed try (Left err) or PlayerServed try
(Left err). Each tick writerSF drains acWriteChan in order with the
tryReadTChan loop of drainChan, looks once, folds serveSender over the
senders, adds the final state, and for each Served: on Right puts
Proceed result into that sender's slot; on Left with TryOne, TryTwo or
TryThree puts TryAgain (rendered error) into that sender's slot; on
Left with TryFailed takes the failure action, then puts TryAgain
(rendered error). DslSender failure action: sendMessageWith
(worldBuilderErrorText err) (priority Emergency), with import
Systemd.Journal (priority, sendMessageWith) and import
System.Posix.Syslog (Priority (Emergency)), then exitFailure.
PlayerSender failure action: for Left (ActorError gid err), the
sessions with sessionGid == Just gid each get Routed sid (SystemMessage
text) and Routed sid (GameNarration narr) with gameErrorText err in
actionConsequence on acOutbound, and writeLog (TickFailed (ActorError
gid err)); for any other Left, writeLog (TickFailed err) alone.
dslTickSF and playerTickBlock lose every lookGameState and addGameState
call. Each builds its function from the drained inputs, writes
DslSender TryOne f or PlayerSender TryOne f to acWriteChan, takes its
slot; on Proceed it does its IO from the result (playerTickBlock:
executeJoinIO over playerResultJoins, the repair rows and the State
views from playerResultState, deliverNarrationIO, the repair replies;
dslTickSF: the DSL reports, the counter write-back); on TryAgain it
resends with the next Try, and after TryThree's TryAgain sends
TryFailed, takes the slot, and carries on. Any other lookGameState or
addGameState call site outside writerSF is removed in this step.
sasha.cabal build-depends gains libsystemd-journal and hsyslog.
sashamud-9b adds the C side to the nix: libsystemd in the package set
and what satisfies libsystemd-journal's pkgconfig-depends. That nix
lands before this step. Tests for the writer: a DslSender and a
PlayerSender write in the same tick both land in the adopted state; a
Left player function leaves the state unchanged. Both tests call
serveSender. SlmRepairSpec's "an unparseable sentence is repaired by
the model and runs" goes back from xit to it in this step and must pass.
