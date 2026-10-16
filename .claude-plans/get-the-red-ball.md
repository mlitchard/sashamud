# Get and drop the red ball

Branch: 17-get-the-red-ball. Written 2026-10-15.

## Goal

Players in the lobby can "get the red ball" and "drop the red ball". World content reaches the server through `deploy-dsl`.

## Rulings

- Use the DSL deploy mechanism (user, 2026-10-15).
- Drop is in scope with get (user, 2026-10-15).
- Infrastructure ships as code; the DSL applies it (user, 2026-10-15). See MEMORY.md CRITICAL RULES.
- "the" may be dropped; the adjective must select among objects that share a noun, so "red ball" tells one ball from another (user, 2026-10-15).
- Adjective matching now; disambiguation ("which ball?") is a later plan of its own (user, 2026-10-15).
- When the typed phrase carries an adjective, the object's _descriptives must hold a phrase with that adjective and noun. In a room with only a white ball, "get the red ball" fails (user, 2026-10-15).
- One adjective per phrase for now. An adjective with a noun names exactly one object in the world: there is one "red ball". "big red ball" comes later (user, 2026-10-15).
- Lookup uses _descriptives only. _shortName and _description are display text and take no part in lookup (user, 2026-10-16; old code: sasha-engine/src/GameState/Spatial.hs:80-95 reads descriptives).
- Pattern-match cleanup included in this plan (user, 2026-10-16).
- Ball changes go in the existing world files; no new .dsl file (user, 2026-10-16).
- sessionGid and sessionSend are the pattern match on SessionPhase; call sites use them. The SignalNetwork.hs and Server.hs items are withdrawn from step 5 (user, 2026-10-16).
- A missing adjective match is a narration to the player, not an error: get narrates "You don't see that here.", drop narrates "You don't have that." (user, 2026-10-16).

## What exists today

- Grammar parses "the red ball" as `DescriptiveNounPhraseDet` (sasha-grammar/src/Grammar/Parser/Composites/Nouns.hs:21-27, Rules.hs:87-90).
- Adjectives declared: SMALL, WHITE only (sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Adjectives.hs:11-14). Lexer has no RED (sasha-grammar/src/Grammar/Lexer.hs:48-58). `Lexeme` has hand-written `Bounded`/`Enum` instances (look-at-player plan).
- The get lookup keeps the noun and drops the adjective: "BALL" in `objectSemanticMap` (sasha/src/Engine/ActionDiscovery/Instances.hs:318-323, :188-189). The drop path's lookup is not yet quoted.
- Get and drop for the ball already exist as DSL: sashamud-world/src/1/World/1-get-drop.dsl and sashamud-world/src/2/Lobby/4-get-drop-ball.dsl. The ball's short name is "ball" (sashamud-world/src/2/Lobby/3-ball.dsl:5).

## Old-code precedent

- No RED and no red ball in old code (/home/mlitchard/gitlab/sasha/sasha-vocabulary/src/Grammar/Parser/Partitions/Adjectives.hs:16: PLANT, POT, WHITE, SMALL).
- Old get and drop both drop the adjective and keep the noun: `parseObjectPhrase` (sasha-engine/src/GameState.hs:142) and `nounPhraseToObjectiveKey` (sasha-engine/src/ActionDiscovery/Instances.hs:1519). Sashamud matches.
- objectSemanticMap is `Map NounKey (Set (GID Object))` (sasha-core/src/Model/Core.hs:1212). NounKey has no adjective (sasha-core/src/Model/Parser/GCase.hs:22). findObjectByKey returns UniqueObject | AmbiguousObjects | NoObject (sasha-engine/src/ActionDiscovery/Instances.hs:1265).
- Adjectives live on the object: world code calls `withGrammar [DescriptiveNounPhrase plant potDS]` (sashamud-world/src/SashaMudWorld/PaveWorld/WestZone/Builders/PlantPot.hs:26, PotPlant.hs:24).
- Object carries `_descriptives :: Set DirectionalStimulusNounPhrase` (sasha-core/src/Model/Core.hs:1226). Filled by `withGrammar` → `Descriptive` constructor → `descriptives %~ insert (DirectionalStimulusNounPhrase atDS descs)` (sasha-dsl/src/DSL/Vocabulary.hs:691, Model/EDSL/SashaLambdaDSL.hs:238, DSL/Builder.hs:866).
- Old matching compares the noun only: `descriptiveMatchesNounKey` (sasha-engine/src/GameState/Spatial.hs:80-95). The adjective comparison has no old-code precedent.
- Old get: `handleSimpleAcquisitionCore` → `locateEntity`, with AmbiguousEntities going to disambiguation (sasha-engine/src/ActionDiscovery/Instances.hs:1009-1035). Old drop: `handleDivestment` → `findObjectInInventory` (Instances.hs:1440-1507).

## Decisions

1. How RED reaches the live server: RULED A (user, 2026-10-15). A server release carries RED. The DSL deploy carries the world content.
2. DSL content: RULED (user, 2026-10-16). modifyObject (ObjectLabel "ball") sets shortName "red ball", description "a red ball that you can get and drop", and the descriptive "red ball". These go in buildBall in sashamud-world/src/2/Lobby/3-ball.dsl (user, 2026-10-16).
3. Tests: RULED (user, 2026-10-16). LoginLogoutSpec, two players, in step 4.
4. Adjective filter: RULED (user, 2026-10-15). Predicate `objectMatchesAdjective`, used by `findMatchingObject :: Adjective -> [GID Object] -> GameComputation Identity (Maybe (GID Object))` via `filterM`, after old sasha-engine/src/GameState/Spatial.hs findMatchingObject.
5. Duplicate descriptives: RULED (user, 2026-10-15). The builder rejects a second object given a descriptive another object already holds.
6. Return type: RULED (user, 2026-10-15). Maybe; one way to fail. Each caller throws with throwMaybeM: get "You don't see that here.", drop "You don't have that."
7. Error constructor: RULED (user, 2026-10-15). `WorldBuilderError` gains `DuplicateDescriptive DirectionalStimulusNounPhrase`, with a case in `worldBuilderErrorText`.
8. Adjective export: RULED (user, 2026-10-16), confirmed by old code. Grammar.Parser.Atomics.Semantics.Adjectives exports the generated `red` as-is, as old sasha-vocabulary/src/Grammar/Parser/Partitions/Adjectives.hs:2 exports plant, pot, white, small.
9. Narration: RULED (user, 2026-10-16). Actor lines become "You pick up the red ball." and "You drop the red ball." Linking adds to the Set (sasha/src/DSL/Builder.hs:308-311) and every outcome runs (sasha/src/Engine/Resolution/ActionManagement.hs:90-95), so the text changes in 4-get-drop-ball.dsl and arrives with the server release. Witness lines read "picks up the red ball" from shortName.
10. World delivery on restart: RULED (user, 2026-10-16). A live server restart delivers the repo world files, so the 4-get-drop-ball.dsl text change reaches the live server with the server release.
11. Adjective extraction: RULED (user, 2026-10-16). No extractor function. Get and drop pattern-match the ObjectPhrase's NounPhrase where they use it: `DescriptiveNounPhrase adj _` and `DescriptiveNounPhraseDet _ adj _` pass `adj` to `findMatchingObject` (with throwMaybeM); `SimpleNounPhrase` and `NounPhrase` keep the existing one/none/many branch unchanged.
12. Semantic map key: WITHDRAWN (user, 2026-10-16). objectSemanticMap keeps its current key; no NounKey step.

## Steps

Step rule: every step builds and is green on its own. Any fix a step needs, including imports, exports, callers, instances and tests, lands in that step.

1. Grammar (Opus):
   - sasha-grammar/src/Grammar/Lexer.hs: RED constructor in Lexeme and `classify "RED" = RED`, following old sasha-core/src/Model/Parser/Lexer.hs:97 and sasha-grammar/src/Grammar/Parser/Lexer.hs:110 (`RED <$ symbol "RED"`), in sashamud's classify shape; the hand-written Bounded/Enum instances on Lexeme cover RED.
   - sasha-grammar/src/Grammar/Parser/Atomics/Semantics/Adjectives.hs: `makeSemanticValues [| Adjective |] [SMALL, WHITE, RED]`, `red` in the adjectives set, and `red` in the export list, following old sasha-vocabulary/src/Grammar/Parser/Partitions/Adjectives.hs:2,16-20 (exports adjectives,plant,pot,white,small).
   - No rule change: old nounPhraseRule/objectPhraseRules (sasha-grammar/src/Grammar/Parser/Rules/Composites/Nouns.hs:149-173) match sashamud Rules.hs:81-90.
2. Descriptives, following the old code (Opus):
   - `Object` (sasha/src/Model/Core.hs:204-209) gains `_descriptives :: Set DirectionalStimulusNounPhrase`, its lens and export, and `mempty` at every `Object` construction.
   - DSL constructor `Descriptive :: NounPhrase DirectionalStimulus -> Object -> SashaLambdaDSL Object` and wrapper `descriptive` (sasha/src/DSL/Model/EDSL/SashaLambdaDSL.hs).
   - Builder case: `descriptives %~ insert (DirectionalStimulusNounPhrase atDS descs)` (sasha/src/DSL/Builder.hs), after old sasha-dsl/src/DSL/Builder.hs:866.
   - Duplicate check in the `Descriptive` builder case, before the insert: when the object already holds the phrase, the insert proceeds (Set insert is a no-op; this keeps `modifyObject` from colliding with itself). Otherwise, when any object in `bsGameState . world . objectMap` holds the phrase, throw `DuplicateDescriptive phrase`. The failure reaches the submitter through the existing DSLBuildFailed path. `WorldBuilderError` gains the constructor and `worldBuilderErrorText` gains its case in this step.
   - DSL.Reify gains `descriptive`, `NounPhrase (DescriptiveNounPhrase)` from Grammar.Parser.Composites.Nouns, `ballDS` from Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus, and `red` from Grammar.Parser.Atomics.Semantics.Adjectives.
   - Any instance the new field touches (NFData, TypeScript derivation, Arbitrary) is fixed in this step.
3. Adjective check (Opus), in sasha/src/Engine/ActionDiscovery/Instances.hs:
   - Get (AcquisitionF instance, sasha/src/Engine/ActionDiscovery/Instances.hs:162-234): after the objectSemanticMap lookup yields the candidates, case on the ObjectPhrase's NounPhrase. `DescriptiveNounPhrase adj _` and `DescriptiveNounPhraseDet _ adj _` → `findMatchingObject adj candidates` with `throwMaybeM "You don't see that here."`. `SimpleNounPhrase` and `NounPhrase` → the existing one/none/many branch.
   - Drop (DivestmentF instance, :236-315): the same case on the inventory candidates, with `throwMaybeM "You don't have that."`.
   - `objectMatchesAdjective` and `findMatchingObject` live in Instances.hs beside parseObjectPhrase.
   - A phrase with no adjective is unfiltered.
   - With one adjective naming one object, the filter yields one object or none. "Which …?" remains for the bare-noun case.
4. World DSL (Opus):
   - sashamud-world/src/2/Lobby/4-get-drop-ball.dsl lines 17-18: the StaticNarration texts become "You pick up the red ball." and "You drop the red ball."
   - sashamud-world/src/2/Lobby/3-ball.dsl buildBall: shortName "red ball", description (colored White "a red ball that you can get and drop"), and descriptive (DescriptiveNounPhrase red ballDS), before `flip objectBehavior lookAtKey`.
   - LoginLogoutSpec: the existing get/drop test's expected text becomes "You pick up the red ball." / "<first> picks up the red ball." / "You drop the red ball." / "<first> drops the red ball."
   - New test in LoginLogoutSpec, same two-player shape: the first player sends "get the red ball" and receives "You pick up the red ball."; the second receives "<first> picks up the red ball.". The first sends "drop the red ball" and receives "You drop the red ball."; the second receives "<first> drops the red ball.".
   - The world file changes reach the live server with the server release (Decision 10).

5. Pattern-match cleanup (Opus), independent of steps 1-4:
   - sasha/src/Engine/Resolution/ActionManagement.hs:212-216: replace the foldl' with `mconcat [s | Supports s <- toList relationships]`.
   - Remove findAVTargetKey (sasha/src/Engine/Resolution/ActionManagement.hs:408-412), identical to findAVKey (user, 2026-10-16). The call at sasha/src/Engine/ActionDiscovery/Instances.hs:214 uses findAVKey. Drop findAVTargetKey from the ActionManagement export list and from the Instances.hs import.

6. Adjective miss narrates (Opus):
   - sasha/src/Engine/ActionDiscovery/Instances.hs get: when findMatchingObject returns Nothing, narrate "You don't see that here." to the actor with modifyAgentNarration actorGid (over actionConsequence (<> [colored White ...])) (the shape of processNarrationEffect, sasha/src/Engine/Resolution/ActionManagement.hs:310-311) and stop; the rest of the get runs only when an object was found. No throw.
   - Drop: the same with "You don't have that."
   - Test: LoginLogoutSpec, the player sends "get the white ball" and receives "You don't see that here."
