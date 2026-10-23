# NounKey: typed semantic-map keys

## Goal

Every semantic-map key in sashamud becomes a NounKey. Today the maps are keyed by Text. The shape follows old sasha. The structure follows sashamud's multiplayer design. Only the constructors sashamud needs now are added.

## Rulings (user)

- Old sasha is the model for every grammar, core, DSL, builder and engine shape. Departures happen only where multiplayer forces them, and each departure is named in this plan.
- NounKey lives in sasha-grammar, Grammar.Parser.GCase, beside VerbKey. It takes the old GCase.hs:22 shape, trimmed to three constructors.
- A new newtype DirectionalStimulusPlayer lives in Grammar.Parser.Atomics.Nouns. Its shape follows old AgentName (old Atomics/Nouns.hs:150-156). The names DirectionalStimulusPlayer and DirectionalStimulusPlayerKey are the user's; sashamud's Model.Core already owns the name AgentKey (Core.hs:278-281).
- VerbKey stays and is used as it is. Its constructor `DirectionalStimulusKey DirectionalStimulusVerb` is renamed `ImperativeKey DirectionalStimulusVerb` (user's name), so the name DirectionalStimulusKey belongs to NounKey. ImplicitStimulusKey, AcquisitionKey and DivestmentKey stay. DirectedImperativeKey comes later.
- Scene gains `_agentSemanticMap :: Map NounKey (Set (GID Agent))`, after old Core.hs:1215. Players enter it at join and leave it at departure, at the same sites that insert into and delete from sceneAgents. Old sasha inserts agents through the DSL (old Builder.hs:659) and deletes them in removeContainedEntity (old GameState.hs:372-378); sashamud's players arrive and leave through the signal network, so the same insert and delete forms live in SignalNetwork.hs.
- All nouns are grammar nouns. No lexeme is added.
- The look path follows old validateObjectLook (old Instances.hs:535) in its objectSemanticMap and agentSemanticMap tiers and its fixed miss string. Old sasha's first tier, the perceptionMap, has no counterpart in sashamud (PerceptionMap was removed from World by earlier ruling). Old sasha keys both maps with DirectionalStimulusKey; sashamud keys the agent map with the player key, by the user's ruling.
- The noun is never rendered into narration text. A miss narrates the fixed string "That's not here. Try something else." through modifyAgentNarration, the mechanism Instances.hs:175 and :224 use today (user, 2026-10-20).
- No disambiguation anywhere (user, 2026-10-20). The engine never asks "Which".
- The DSL registration follows old registerObjectToScene (old SashaLambdaDSL.hs:632) and old SashaMudWorld.hs:325.
- Every step builds and is green on its own. Any fix a step needs, including imports, exports, callers, instances, .dsl files and tests, lands in that step.

## What exists today (sashamud)

- `sasha/src/Model/Core.hs:244-254` Scene: `_title`, `_sceneDescription`, `_objectSemanticMap :: Map Text (Set (GID Object))`, `_sceneObjects`, `_sceneActionManagement`, `_sceneAgents`; `deriving stock (Eq, Generic, Ord, Show)`, `deriving anyclass (NFData)`.
- `Core.hs:278-281` `newtype AgentKey = AgentKey (GID Agent)`.
- `Core.hs:305-321` World: `_globalSemanticMap :: Map Text (Set (GID Object))` at :309; `deriving stock (Eq, Ord, Show)` at :318; hand-written NFData instance at :320-321 listing every field.
- `Core.hs:527-535` defaultScene, the only Scene literal in the repo. `Core.hs:589` `makeLenses ''Scene`. Export list entries for objectSemanticMap and globalSemanticMap at :92 and :102.
- No ToJSONKey, FromJSONKey, TypeScript or Arbitrary instance touches Scene, World or the semantic maps. `sasha/test/ArbitraryOrphans.hs:28,51` and `sasha/test/JSONSpec.hs:25,95` import and use VerbKey only.
- `sasha-grammar/src/Grammar/Parser/GCase.hs`: exports `VerbKey (DirectionalStimulusKey, ImplicitStimulusKey, AcquisitionKey, DivestmentKey)`; imports Grammar.Parser.Atomics.Verbs; VerbKey derives stock (Eq, Generic, Ord, Show) and anyclass (FromJSON, FromJSONKey, NFData, ToJSON, ToJSONKey).
- `sasha-grammar/src/Grammar/Parser/Atomics/Nouns.hs:22` `newtype DirectionalStimulus = DirectionalStimulus { _fromDirectionalStimulus :: Lexeme }` deriving stock (Eq, Ord, Show), newtype (FromJSON, Hashable, NFData, ToJSON); HasLexeme instance at :26. `:30` `newtype Objective = Objective { _fromObjective :: Lexeme }` deriving stock (Eq, Ord, Show), newtype (Hashable, NFData); HasLexeme at :34. The module imports `Grammar.Lexer (HasLexeme (toLexeme), Lexeme)` and exports only the two newtypes.
- Vocabulary values: `sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Nouns/DirectionalStimulus.hs:17-21` defines `ballDS`, `floorDS`; `.../Semantics/Nouns/Objective.hs:15-19` defines `ballOB`, `floorOB`.
- `sasha-grammar/src/Grammar/Lexer.hs:60` `AGENTNAME Text`.
- `sasha-grammar/src/Grammar/Parser/Composites/Nouns.hs:36-40` DirectionalStimulusNounPhrase; `:42-45` `PlayerName` newtype over Text.
- `sasha/src/Engine/ActionDiscovery/Instances.hs:137-251` DirectionalStimulusF instance. `:144` `mkVerbKey (verb, _) = DirectionalStimulusKey verb`. Object branch :150-199: `:151 let nounText = extractDirectionalNoun nounPhrase`, `:158 lookup nounText (view objectSemanticMap scene)`, `_ -> throwError ("Which " <> nounText <> "?")` at :168 and :172, miss at :175 `modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't see that here."]))`, then fetch and dispatch through :199. Player branch :201-251: scans sceneAgents comparing `toPlainText (view agentShortName agent) == nameText` at :219, miss narrates `"you don't see " <> nameText <> " here"` at :224 through modifyAgentNarration, `"Which " <> nameText <> "?"` at :228, then continues with the found GID at :229-251.
- `Instances.hs:254-264` `extractDirectionalNoun :: DirectionalStimulusNounPhrase -> Text`; object branch `pack (show (toLexeme ds))`; player branch `PlayerDirectionalStimulusNounPhrase _ (PlayerNamePhrase np)` returns `name` from `PlayerName name`.
- `Instances.hs:469-474` `parseObjectPhrase :: ObjectPhrase -> Text`, used at :286 and :388. Semantic-map sites: :85 and :89 imports, :293 get (objectSemanticMap) with `_ -> throwError ("Which " <> nounText <> "?")` at :308 and :312, :389 drop (globalSemanticMap) with the same at :407 and :411, :429 floor `lookup (pack (show (toLexeme floorOB))) (view objectSemanticMap scene)`. `pack` and `show` are used throughout the file for other messages.
- `sasha/src/Engine/Resolution/ActionManagement.hs`: `addObjectToScene` :263-268 folds `insertWith (<>) nk (Data.Set.singleton oid)` over objectSemanticMap; `removeObjectFromScene` :270-275 folds `over objectSemanticMap . adjust (Data.Set.delete oid)`; `findNounKeysForObject :: GID Object -> GameComputation Identity [Text]` :277-280 reads globalSemanticMap. Lines :74 and :77 import globalSemanticMap and objectSemanticMap from Model.Core.
- `sasha/src/Engine/Resolution/Perception.hs:67` reads a semantic map with `elems semMap`; export entry at :30.
- `sasha/src/DSL/Model/EDSL/SashaLambdaDSL.hs:94` `RegisterObjectToScene :: GID Scene -> GID Object -> Text -> SashaLambdaDSL ()`; `:166-167` `registerObjectToScene` with the same type. `sasha/src/DSL/Builder.hs:253-264` interprets it: `objectSemanticMap . at nounText . non mempty %~ Data.Set.insert objGID` at :259 and `world . globalSemanticMap . at nounText . non mempty %~ Data.Set.insert objGID` at :263. `Builder.hs:40` imports and `:340,:342` use VerbKey's DirectionalStimulusKey. Builder imports `at, non, (%~)` from Lens.Micro.Platform at :42.
- `sasha/src/DSL/Reify.hs:88` lists `"registerObjectToScene"`; `:102-103` `ModuleImport "Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus" NotQualified (ImportList ["ballDS"])`; no entry for the Objective semantics module and none for Grammar.Parser.Atomics.Nouns; `:114-115` GCase ImportList `["VerbKey (AcquisitionKey, DirectionalStimulusKey, DivestmentKey, ImplicitStimulusKey)"]`; `:116-143` Model.Core ImportList.
- `sasha/src/Engine/Simulation/SignalNetwork.hs:329-331`: a Left from the tick computation is written to stderr and no narration is delivered that tick. `:361-389` processLeavesPure; applyDeparture (:377-388) computes `remaining`, `scene' = set sceneAgents remaining scene`, and departNarr with `[ ... | gid <- Set.toList departed, Just a <- [lookup gid aMap] ]` using `view agentShortName a`. `:401-452` joinComputation: ReturningPlayerJoined has `agent` and uses `toPlainText (view agentShortName agent)` at :417; NewPlayerJoined binds `agent = mkAgent (view unPlayerNameVAL name)` at :439; both do `scene' = set sceneAgents (Set.insert gid (view sceneAgents scene)) scene`. Imports: Data.Map.Strict at :49-58 (Map, alter, assocs, elems, fromList, insert, lookup, unionWith); `Data.Set (Set)` at :62, `qualified Data.Set (toList)` at :63, `qualified Data.Set as Set (delete, filter, fromList, insert, member, null, toList)` at :64-72; `Grammar.Lexer (Lexeme (AGENTNAME, UNKNOWN), lexify, tokens)` at :110; `Grammar.Parser.Composites.Nouns (PlayerName (PlayerName))` at :112; Lens.Micro.Platform at :114-123 (at, over, set, use, view, (.=), (.~), (?~)); Model.Core list at :124-157; `Model.RichText (RichText, TextColor (White), colored, plain, toPlainText)` at :161-167. GCase and Atomics.Nouns are not imported.
- World files: `sashamud-world/src/2/Lobby/2-floor.dsl:12` `registerObjectToScene lobbyGID floorGID "FLOOR"`; `3-ball.dsl:13` `registerObjectToScene lobbyGID ballGID "BALL"`.
- Tests asserting look messages: `sashamud-server/test-e2e/LookAtPlayerSpec.hs:82` checks `text.includes("you don't see bootstrap here")` inside a GameNarration's `_actionConsequence`. `sashamud-server/test/Integration/LoginLogoutSpec.hs:620` asserts "You don't see that here." on the get path.

## Old-code precedent (old sasha)

- `sasha-core/src/Model/Parser/GCase.hs:22` NounKey (thirteen constructors, including `AgentKey AgentName` at :34), `:39` VerbKey.
- `sasha-core/src/Model/Parser/Atomics/Nouns.hs:150-156` `newtype AgentName = AgentName { _fromAgentName :: Lexeme }`.
- `sasha-core/src/Model/Core.hs:1212` objectSemanticMap, `:1215` agentSemanticMap, `:1277` globalSemanticMap, all keyed by NounKey.
- `sasha-engine/src/ActionDiscovery/Instances.hs:535-555` validateObjectLook: perceptionMap tier, then `findAccessibleObject (DirectionalStimulusKey noun)`, then `Data.Map.Strict.lookup (DirectionalStimulusKey noun) agentSemMap` with `Data.Set.elemAt 0` on a non-empty set, miss `throwError "That's not here. Try something else."`. There is no disambiguation branch.
- `Instances.hs:558` `extractDirectionalNoun :: DirectionalStimulusNounPhrase -> DirectionalStimulus`. `:339` somaticNounPhraseToKey. `:467` DirectionalStimulusF instance.
- `GameState.hs:142` `parseObjectPhrase :: ObjectPhrase -> NounKey`. `GameState.hs:372-378` removeContainedEntity deletes an agent from agentSemanticMap with `foldr (Data.Map.Strict.adjust (delete childAid)) m agentNounKeys` beside `sceneAgents %~ delete childAid`.
- `sasha-dsl/src/Model/EDSL/SashaLambdaDSL.hs:264` `RegisterObjectToScene :: GID Scene -> GID Object -> NounKey -> SashaLambdaDSL ()`; `:632` `registerObjectToScene :: GID Scene -> GID Object -> NounKey -> SashaLambdaDSL ()`, `registerObjectToScene = RegisterObjectToScene`.
- `sasha-dsl/src/DSL/Builder.hs:718` interprets RegisterObjectToScene with `objectSemanticMap . at nounKey . non mempty %~ Data.Set.insert objGID` and `globalSemanticMap . at nounKey . non mempty %= Data.Set.insert objGID`. `:659` interprets RegisterAgentToScene with `agentSemanticMap . at nounKey . non mempty %~ Data.Set.insert agentGID` and `sceneAgents %~ Data.Set.insert agentGID`.
- `sashamud-world/src/SashaMudWorld.hs:325`:

      registerObjectToScene objs.arcadeGID objs.arcadeFloorGID (DirectionalStimulusKey floorDS)
      registerObjectToScene objs.arcadeGID objs.arcadeFloorGID (ObjectiveKey floorOB)

## Decisions

### D1 RULED (user, 2026-10-19): NounKey shape

In Grammar.Parser.GCase:

    type NounKey :: Type
    data NounKey = DirectionalStimulusKey DirectionalStimulus
                 | DirectionalStimulusPlayerKey DirectionalStimulusPlayer
                 | ObjectiveKey Objective
      deriving stock (Eq, Generic, Ord, Show)
      deriving anyclass (NFData)

No JSON, TypeScript or Arbitrary instance: nothing that holds a NounKey derives one, and Objective carries no JSON instance.

### D2 RULED (user, 2026-10-19): VerbKey

VerbKey stays. `DirectionalStimulusKey DirectionalStimulusVerb` becomes `ImperativeKey DirectionalStimulusVerb`. Every other constructor is unchanged.

### D3 RULED (user, 2026-10-19): world keys

No lexeme is added. The lobby floor registers under `DirectionalStimulusKey floorDS` and `ObjectiveKey floorOB`. The lobby ball registers under `DirectionalStimulusKey ballDS` and `ObjectiveKey ballOB`. Each object has one registerObjectToScene line per key, as old SashaMudWorld.hs:325. Builder's insert is additive per key.

### D4 RULED (user, 2026-10-19): the player key and the look path

In Grammar.Parser.Atomics.Nouns, after old AgentName's shape:

    type DirectionalStimulusPlayer :: Type
    newtype DirectionalStimulusPlayer = DirectionalStimulusPlayer { _fromDirectionalStimulusPlayer :: Lexeme }
      deriving stock (Eq, Ord, Show)
      deriving newtype (FromJSON, Hashable, NFData, ToJSON)

    instance HasLexeme DirectionalStimulusPlayer where
      toLexeme = _fromDirectionalStimulusPlayer

Its Lexeme is `AGENTNAME name`. A player's key is `DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME name))`. The name text at every engine site is `toPlainText (view agentShortName agent)`, the text today's player look already compares against at Instances.hs:219.

`extractDirectionalNoun :: DirectionalStimulusNounPhrase -> NounKey`. The object branch gives `DirectionalStimulusKey ds`. The player branch gives the player key built from `name`.

The look path keys objectSemanticMap for the object branch and agentSemanticMap for the player branch. A key absent from the map, or present with an empty set, narrates "That's not here. Try something else." through modifyAgentNarration, as :175 does today. A found GID proceeds as today's code does after it has its GID. The noun is never rendered into a message.

### D5 RULED (user, 2026-10-20): no disambiguation

The engine never asks "Which". The seven lines at Instances.hs:168, :172, :228, :308, :312, :407, :411 are removed. Where a lookup yields a set, the match is `case Set.toList set of [] -> miss; (gid : _) -> proceed with gid`, which is old validateObjectLook's `elemAt 0` written as a total match. The get and drop miss messages stay as they are. The look miss message is the D4 string.

### D6 RULED (user, 2026-10-20): the test world's table and cup

The study scene, table and cup are test-only. They stay. Their registerObjectToScene lines take NounKey values. The vocabulary gains TABLE and CUP lexemes and the values tableDS, cupDS, tableOB and cupOB, each beside the ball and floor entries in the same file. The lobby world keys stay floor and ball. D3's "No lexeme is added" is amended by this ruling. Old-code precedent: old sasha-core/src/Model/Parser/Lexer.hs:146 has TABLE; old sasha-vocabulary/src/Grammar/Parser/Partitions/Nouns/DirectionalStimulus.hs defines `tableDS = table` and Objectives.hs defines `tableOB = table`; old Arcade/Registration.hs:381-382 registers the table under `DirectionalStimulusKey tableDS` and `ObjectiveKey tableOB`. Old sasha has no cup; cup follows table's shape by this ruling.

## Steps

Step rule: every step builds and is green on its own. Any fix a step needs, including imports, exports, callers, instances, .dsl files and tests, lands in that step.

### Step 1: NounKey and the VerbKey rename (sasha-grammar and its importers)

1. `sasha-grammar/src/Grammar/Parser/Atomics/Nouns.hs`: add the DirectionalStimulusPlayer newtype and HasLexeme instance from D4 after the DirectionalStimulus block. Add `DirectionalStimulusPlayer (DirectionalStimulusPlayer, _fromDirectionalStimulusPlayer)` to the export list.
2. `sasha-grammar/src/Grammar/Parser/GCase.hs`: add NounKey from D1. Export `NounKey (DirectionalStimulusKey, DirectionalStimulusPlayerKey, ObjectiveKey)`. Rename VerbKey's first constructor to `ImperativeKey`, export list included. Import `Grammar.Parser.Atomics.Nouns (DirectionalStimulus, DirectionalStimulusPlayer, Objective)`.
3. Callers of the renamed constructor: `sasha/src/DSL/Builder.hs:40` import and `:340`, `:342` uses; `sasha/src/Engine/ActionDiscovery/Instances.hs:53` import and `:144` `mkVerbKey`; `sasha/src/DSL/Reify.hs:115` list entry becomes `"VerbKey (AcquisitionKey, DivestmentKey, ImperativeKey, ImplicitStimulusKey)"`.
4. Tests: ArbitraryOrphans.hs and JSONSpec.hs name VerbKey only; the GenericArbitrary derivation covers the rename. No test edit.

Green: sasha-grammar builds with the new type and newtype; sasha builds with the rename at every caller.

### Step 2: NounKey in the maps, the DSL, the engine, the join and leave sites, the world files and the tests

1. `sasha/src/Model/Core.hs`: `_objectSemanticMap :: Map NounKey (Set (GID Object))`; add `_agentSemanticMap :: Map NounKey (Set (GID Agent))` to Scene after `_objectSemanticMap`; `_globalSemanticMap :: Map NounKey (Set (GID Object))`. Import `NounKey` from Grammar.Parser.GCase beside VerbKey. defaultScene at :527-535 gains `_agentSemanticMap = mempty`. Export `agentSemanticMap` beside objectSemanticMap at :92. The World NFData instance at :320-321 is unchanged.
2. `sasha/src/DSL/Model/EDSL/SashaLambdaDSL.hs:94` RegisterObjectToScene and `:166` registerObjectToScene take `NounKey` where they took Text, as old SashaLambdaDSL.hs:264 and :632. `sasha/src/DSL/Builder.hs:253-264` inserts under the NounKey at :259 and :263 with the same `at key . non mempty %~ Data.Set.insert objGID` form, as old Builder.hs:718. Both files import `NounKey` from Grammar.Parser.GCase.
3. `sasha/src/DSL/Reify.hs`: add `"NounKey (DirectionalStimulusKey, DirectionalStimulusPlayerKey, ObjectiveKey)"` to the GCase ImportList at :114-115; add `ModuleImport "Grammar.Parser.Atomics.Nouns" NotQualified (ImportList ["DirectionalStimulus", "DirectionalStimulusPlayer", "Objective"])`; add `"floorDS"` to the DirectionalStimulus entry at :102-103; add `ModuleImport "Grammar.Parser.Atomics.Semantics.Nouns.Objective" NotQualified (ImportList ["ballOB", "floorOB"])`; add `agentSemanticMap` to the Model.Core list at :116-143.
4. `sasha/src/Engine/ActionDiscovery/Instances.hs`: `extractDirectionalNoun` at :254-264 returns NounKey per D4. Object look branch :150-199 keys objectSemanticMap by that NounKey; the :168 and :172 lines are removed per D5; a missing key and an empty set reach the :175 modifyAgentNarration, whose text becomes "That's not here. Try something else."; a found GID continues through :199 as today. Player look branch :201-251 keys `view agentSemanticMap scene` by the NounKey in place of the sceneAgents scan at :219; the :228 line is removed per D5; the :224 modifyAgentNarration text becomes "That's not here. Try something else."; a found GID continues through :251 as today. `parseObjectPhrase` at :469-474 returns `ObjectiveKey` of the phrase's Objective, as old GameState.hs:142. Get at :293 and drop at :389 look up by that NounKey; the :308, :312, :407, :411 lines are removed per D5 and the set is matched `[]` for miss and `(gid : _)` for found; their miss messages are unchanged. Floor at :429 looks up `ObjectiveKey floorOB`. Imports at :85 and :89 follow; `NounKey (DirectionalStimulusKey, DirectionalStimulusPlayerKey, ObjectiveKey)` joins the GCase import at :53; `DirectionalStimulusPlayer (DirectionalStimulusPlayer)` is imported from Grammar.Parser.Atomics.Nouns; `AGENTNAME` is imported from Grammar.Lexer. `pack` and `show` stay.
5. `sasha/src/Engine/Resolution/ActionManagement.hs:277-280` findNounKeysForObject returns `[NounKey]`; import `NounKey` from Grammar.Parser.GCase. addObjectToScene :263-268 and removeObjectFromScene :270-275 follow the key type with no edit. Perception.hs:67 has no edit.
6. `sasha/src/Engine/Simulation/SignalNetwork.hs`: in joinComputation, each `scene'` also gains `& agentSemanticMap . at key . non mempty %~ Set.insert gid` where `key = DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME (toPlainText (view agentShortName agent))))`, the insert form of old Builder.hs:659; ReturningPlayerJoined uses its `agent`, NewPlayerJoined uses the `agent` bound at :439. In applyDeparture, `scene'` also gains, for each departed gid with `Just a <- [lookup gid aMap]`, `over agentSemanticMap (adjust (Set.delete gid) key)` with key built the same way from `a`, the delete form of old GameState.hs:378 and of sashamud's ActionManagement.hs:275. Imports: `adjust` joins Data.Map.Strict at :49-58; `non` and `(%~)` join Lens.Micro.Platform at :114-123; `NounKey (DirectionalStimulusPlayerKey)` from Grammar.Parser.GCase; `DirectionalStimulusPlayer (DirectionalStimulusPlayer)` from Grammar.Parser.Atomics.Nouns; `agentSemanticMap` joins the Model.Core list at :124-157. AGENTNAME and toPlainText are already imported at :110 and :161-167.
7. World files, per D3: `sashamud-world/src/2/Lobby/2-floor.dsl:12` becomes two lines, `registerObjectToScene lobbyGID floorGID (DirectionalStimulusKey floorDS)` and `registerObjectToScene lobbyGID floorGID (ObjectiveKey floorOB)`. `3-ball.dsl:13` becomes `registerObjectToScene lobbyGID ballGID (DirectionalStimulusKey ballDS)` and `registerObjectToScene lobbyGID ballGID (ObjectiveKey ballOB)`.
8. Tests: `sashamud-server/test-e2e/LookAtPlayerSpec.hs:82` asserts "That's not here. Try something else." in place of "you don't see bootstrap here". `LoginLogoutSpec.hs:620` is unchanged.
9. `sasha-grammar/src/Grammar/Lexer.hs`: in the Lexeme type, `CUP` after `BALL` and `TABLE` after `SMALL`, matching the existing alphabetical order. In `classify`, `classify "cup" = CUP` after the "ball" line and `classify "table" = TABLE` after the "small" line.
10. `sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Nouns/DirectionalStimulus.hs`: the export list gains `cupDS` and `tableDS` beside `ballDS` and `floorDS`; the Lexeme import becomes `Lexeme (BALL, CUP, FLOOR, TABLE)`; the makeSemanticValues list becomes `[BALL, CUP, FLOOR, TABLE]`; `cupDS :: DirectionalStimulus` with `cupDS = cup` and `tableDS :: DirectionalStimulus` with `tableDS = table` sit beside `ballDS` and `floorDS` in the same form; `directionalStimuli = fromList [ball, cup, floor, table]`.
11. `sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Nouns/Objective.hs`: the same change with `cupOB`, `tableOB`, `Objective`, and `objectives = fromList [ball, cup, floor, table]`.
12. `sasha/src/DSL/Reify.hs`: the DirectionalStimulus semantics ImportList from point 3 is `["ballDS", "cupDS", "floorDS", "tableDS"]`; the Objective semantics ImportList from point 3 is `["ballOB", "cupOB", "floorOB", "tableOB"]`.
13. `sashamud-server/test-e2e/study.dsl:7-8` become four lines: `registerObjectToScene studyGID tableGID (DirectionalStimulusKey tableDS)`, `registerObjectToScene studyGID tableGID (ObjectiveKey tableOB)`, `registerObjectToScene studyGID cupGID (DirectionalStimulusKey cupDS)`, `registerObjectToScene studyGID cupGID (ObjectiveKey cupOB)`. `sashamud-server/test/Integration/LoginLogoutSpec.hs:868-869` become the same four lines inside the string list, with the file's quoting and indentation.

Green: full build, sasha tests, world tests, integration and e2e. Files Step 2 touches: sasha/src/Model/Core.hs, sasha/src/DSL/Model/EDSL/SashaLambdaDSL.hs, sasha/src/DSL/Builder.hs, sasha/src/DSL/Reify.hs, sasha/src/Engine/ActionDiscovery/Instances.hs, sasha/src/Engine/Resolution/ActionManagement.hs, sasha/src/Engine/Simulation/SignalNetwork.hs, sasha-grammar/src/Grammar/Lexer.hs, sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Nouns/DirectionalStimulus.hs, sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Nouns/Objective.hs, sashamud-world/src/2/Lobby/2-floor.dsl, sashamud-world/src/2/Lobby/3-ball.dsl, sashamud-server/test-e2e/study.dsl, sashamud-server/test/Integration/LoginLogoutSpec.hs, sashamud-server/test-e2e/LookAtPlayerSpec.hs.
