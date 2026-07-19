# Look At Player — Agent-Targeted Directional Stimulus

**STATUS: Approved** 

## Summary

"look at ball" (object path) is complete. This plan adds "look at <playername>" — the agent path. A new `PLAYERNAME Text` lexeme catches any unrecognized word. The parser produces a new `StimulusVerbPhrase` constructor carrying the verb and raw Text. Resolution at runtime looks up the name against agents in the current scene. The veto chain mirrors the object path: player + target agent + scene. Witnesses see "{actor} looks at {target}."

## Design decisions (user-ruled)

- `PLAYERNAME Text` on `Lexeme` — raw Text, not PlayerNameVAL (cross-package boundary)
- Hand-written `Bounded` and `Enum` instances on `Lexeme` (cover keyword constructors only)
- Case-insensitive resolution: lexer uppercases input, resolution compares via `toUpper` on `agentShortName`
- No fallback concept — PLAYERNAME is a first-class Lexeme constructor for any unrecognized word
- Agent path bypasses `ActionProtocol` — standalone resolution, reuses `DirectionalStimulusF` for the veto chain
- No SashaMudWorld.hs changes needed — existing DSA management on denizens already serves the target veto

## Constructor name: needs user approval

The new `StimulusVerbPhrase` constructor has no old code precedent (old code resolved agent vs object at runtime, not at parse time). Proposed: **`AgentStimulusVerbPhrase DirectionalStimulusVerb Text`** — follows the `DirectStimulusVerbPhrase` naming pattern. Open to renaming.

---

## File 1: `sasha-grammar/src/Grammar/Lexer.hs`

### Changes

**Add `PLAYERNAME Text` constructor to `Lexeme`:**

```haskell
data Lexeme
  = AT
  | BALL
  | FLOOR
  | LOOK
  | PLAYERNAME Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Hashable, NFData)
```

Remove `Bounded, Enum` from deriving clause. Remove `GHC.Enum` import.

**Hand-written `Bounded` instance:**


We need a `Bounded` instance for `Lexeme` to support the existing test that uses
`enumFromTo minBound maxBound`. Investigate Converting the Text to string and
then apply maxBound to Char
```haskell
instance Bounded Lexeme where
  minBound = AT
  maxBound = PlayerName "sasha" we need something better than this
```

**Hand-written `Enum` instance** (covers keyword constructors only):

```haskell
instance Enum Lexeme where
  toEnum 0 = AT
  toEnum 1 = BALL
  toEnum 2 = FLOOR
  toEnum 3 = LOOK
  toEnum 4 = PlayerName "sasha"

  fromEnum AT   = 0
  fromEnum BALL = 1
  fromEnum FLOOR = 2
  fromEnum LOOK  = 3
  fromEnum (PLAYERNAME _) = 4
```

**Replace `term` with word-then-classify approach:**

```haskell
term :: Lexer Lexeme
term = classify <$> word
  where
    classify "AT"    = AT
    classify "BALL"  = BALL
    classify "FLOOR" = FLOOR
    classify "LOOK"  = LOOK
    classify w       = PLAYERNAME w

word :: Lexer Text
word = Lexer (pack <$> some alphaNumChar) <* sc
```

Parse any alphanumeric word first, then classify. "ATLAS" is consumed as one word and becomes `PLAYERNAME "ATLAS"`. No `try`, no `notFollowedBy`, no word boundary machinery. `sym` becomes unused (leave in place or remove — user call).

**New imports:**

- `some` from `Control.Applicative`
- `alphaNumChar` from `Text.Megaparsec.Char`

**Removable imports** (no longer used by `term`, only by `sym` which is now dead):

- `symbol` from `Text.Megaparsec.Char.Lexer`
- `(<|>)` from `Control.Applicative` (still used? check)
- `(<$)` from `Data.Functor` (still used? check)

`PLAYERNAME` is auto-exported via existing `Lexeme (..)` export. No export change needed.

---

## File 2: `sasha-grammar/src/Grammar/Parser/Composites/Model.hs`

### Changes

**Add new constructor to `StimulusVerbPhrase`:**

```haskell
data StimulusVerbPhrase = ImplicitStimulusVerb ImplicitStimulusVerb
                        | DirectStimulusVerbPhrase DirectionalStimulusVerb DirectionalStimulusNounPhrase
                        | AgentStimulusVerbPhrase DirectionalStimulusVerb 'This cant be a raw text, we need to think about the solution'
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
```

New import: `Data.Text (Text)`.

Export: add `AgentStimulusVerbPhrase` to the `StimulusVerbPhrase (..)` export.

---

## File 3: `sasha-grammar/src/Grammar/Parser/Composites/Rules.hs`

### Changes

**Add Earley rule for `LOOK AT PLAYERNAME`** in `stimulusVerbPhraseRules`:

```haskell
stimulusVerbPhraseRules :: Grammar r (Prod r Text Lexeme StimulusVerbPhrase)
stimulusVerbPhraseRules = do
  implicitStimulusVerb <- implicitStimulusVerbRule implicitStimulusVerbs
  directionalStimulusVerb <- directionalStimulusVerbRule directionalStimulusVerbs
  directionalStimulusMarker <- directionalStimulusMarkerRule directionalStimulusMarkers
  directionalStimulus <- directionalStimulusRule directionalStimuli
  playerName <- playerNameRule
  rule $ ImplicitStimulusVerb <$> implicitStimulusVerb
     <|> DirectStimulusVerbPhrase
           <$> directionalStimulusVerb
           <*> (DirectionalStimulusNounPhrase
                  <$> directionalStimulusMarker
                  <*> (SimpleNounPhrase <$> directionalStimulus))
     <|> AgentStimulusVerbPhrase
           <$> directionalStimulusVerb
           <* directionalStimulusMarker
           <*> playerName
```

The `<*` discards the AT token (consumed but not stored). The parser matches LOOK + AT + PLAYERNAME, producing `AgentStimulusVerbPhrase (DirectionalStimulusVerb LOOK) "RAJ"`.

**Add `playerNameRule`:**

This cant be a raw Text
```haskell
playerNameRule :: Grammar r (Prod r Text Lexeme Text)
playerNameRule = rule . terminal $ \case
  PLAYERNAME txt -> Just txt
  _              -> Nothing
```

No ambiguity: BALL lexes as `BALL` (not `PLAYERNAME "BALL"`), so "look at ball" can only match `DirectStimulusVerbPhrase`. "look at raj" produces `[LOOK, AT, PLAYERNAME "RAJ"]`, and only `AgentStimulusVerbPhrase` matches.

**New imports:**

- `Grammar.Lexer (Lexeme (PLAYERNAME))` — add PLAYERNAME to existing Lexeme import
- `Text.Earley.Grammar (terminal)` — add to existing import
- `Grammar.Parser.Composites.Model (AgentStimulusVerbPhrase)` — add to existing import

---

## File 4: `sasha-grammar/test/Test/Lexer.hs`

### Changes

Existing test uses `enumFromTo minBound maxBound` — still works with hand-written `Bounded`/`Enum` (produces `[AT, BALL, FLOOR, LOOK]`).

**Add a test for PLAYERNAME lexing:**

```haskell
it "lexer parses unrecognized word as PLAYERNAME" $
  lexify tokens "RAJ" `shouldBe` Right [PLAYERNAME "RAJ"]

it "lexer parses look at playername" $
  lexify tokens "look at raj" `shouldBe` Right [LOOK, AT, PLAYERNAME "RAJ"]
```

New import: `Grammar.Lexer (PLAYERNAME)` — add to existing import.

---

## File 5: `sasha/src/Model/Core.hs`

### Changes

**Add `AgentWitnessContext` to `WitnessContext`:**

```haskell
data WitnessContext = ImplicitWitnessContext
                    | DirectedWitnessContext (GID Object)
                    | AgentWitnessContext (GID Agent)
```

Export `AgentWitnessContext` — add to the `WitnessContext (..)` export list.

---

## File 6: `sasha/src/Engine/Evaluators/Player/General.hs`

### Changes

**Add case for new constructor in `evalStimulusVerbPhrase`:**

Can we use PlaterNameVal instead of raw text
```haskell
evalStimulusVerbPhrase actorGid (AgentStimulusVerbPhrase verb playerNameText) =
  manageAgentStimulusProcess actorGid verb playerNameText
```

**New imports:**

- `Grammar.Parser.Composites.Model (AgentStimulusVerbPhrase)` — add to existing import
- `Engine.ActionDiscovery.Percieve.Look (manageAgentStimulusProcess)` — add to existing import

---

## File 7: `sasha/src/Engine/ActionDiscovery/Percieve/Look.hs`

### Changes

**Add `manageAgentStimulusProcess`** — the agent-targeted look flow.
This is the core of the feature. It bypasses `ActionProtocol`
because the resolution is fundamentally different from the object
path (sceneAgents + name matching vs globalSemanticMap).

```haskell
manageAgentStimulusProcess :: GID Agent
                           -> DirectionalStimulusVerb
                           -> Text -- Can this be PlayerNameVAL
                           -> GameComputation Identity ()
manageAgentStimulusProcess actorGid verb playerNameText = do
  -- Resolve target agent by name in current scene
  aMap <- use (world . agentMap . getAgentMap)
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
             (lookup sceneGid sMap)

  let candidates =
        [ gid
        | gid <- toList (view sceneAgents scene)
        , gid /= actorGid
        , Just agent <- [lookup gid aMap]
        , toUpper (toPlainText (view agentShortName agent)) == playerNameText
        ]
  targetGid <- case candidates of
    [gid] -> pure gid
    []    -> throwError ("Nobody called \"" <> playerNameText <> "\" here.")
    _     -> throwError ("Which " <> playerNameText <> "?")

  -- Fetch action map
  actionMap <- gets (getActionMap @DirectionalStimulusF . view actionMaps)

  -- Player veto
  actor <- throwMaybeM ("Agent not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  playerActionGID <- throwMaybeM ("Agent: " <> noGIDError @DirectionalStimulusF)
                       (lookupDirectionalStimulus verb (view agentActionManagement actor))
  playerAction <- fetchAction @DirectionalStimulusF actionMap playerActionGID

  -- Target agent veto
  target <- throwMaybeM ("Agent not found: " <> pack (show targetGid))
              (lookup targetGid aMap)
  targetActionGID <- throwMaybeM ("Target has no look-at action")
                       (lookupDirectionalStimulus verb (view agentActionManagement target))
  targetAction <- fetchAction @DirectionalStimulusF actionMap targetActionGID

  -- Scene veto
  sceneActionGID <- throwMaybeM ("Scene: " <> noGIDError @DirectionalStimulusF)
                      (lookupDirectionalStimulus verb (view sceneActionManagement scene))
  sceneAction <- fetchAction @DirectionalStimulusF actionMap sceneActionGID

  let playerKey = mkEffectKey @DirectionalStimulusF playerActionGID
      targetKey = mkEffectKey @DirectionalStimulusF targetActionGID
      sceneKey  = mkEffectKey @DirectionalStimulusF sceneActionGID

      
  case (playerAction, targetAction, sceneAction) of
    (DirectionalNoStimulusF pf, _, _) ->
      pf actorGid playerKey
    (_, DirectionalNoStimulusF tf, _) ->
      tf actorGid targetKey
    (_, _, DirectionalNoStimulusF sf) ->
      sf actorGid sceneKey
    (DirectionalStimulusF ps, DirectionalStimulusF ts, DirectionalStimulusF ls) -> do
      ps actorGid playerKey
      ts actorGid targetKey
      ls actorGid sceneKey
      -- Render target agent description (old code: Instances.hs:523-525)
      modifyAgentNarration actorGid
        (over actionConsequence (<> [view agentDescription target]))
      -- Fire witnesses
      processWitnesses actorGid (DirectionalStimulusKey verb) (AgentWitnessContext targetGid)
```

**Key design notes:**

- Resolution inlines directly — no helper function (old code pattern: resolution was inside `validateObjectLook`, not a separate helper)
- Reuses `lookupDirectionalStimulus` for all three veto lookups (player, target, scene all have `DSAManagementKey` entries)
- Reuses `fetchAction @DirectionalStimulusF` from Protocol.hs
- After veto passes: renders `agentDescription` directly (not via world outcomes), matching old code pattern (Instances.hs:523-525)
- `processActionOutcomeRegistry` fires for player/target/scene keys but produces no-ops (no world outcomes linked to those GIDs for agent-targeted look)

**New imports** (in addition to existing):

- `Control.Monad.Except (throwError)`
- `Control.Monad.State (gets)`
- `Data.Map.Strict (lookup)`
- `Data.Text (toUpper)`
- `Engine.ActionDiscovery.Protocol (ActionProtocol (getActionMap, mkEffectKey), fetchAction, noGIDError)`
- `Engine.Resolution.ActionManagement (lookupDirectionalStimulus, processWitnesses)`
- `Engine.Resolution.Perception (modifyAgentNarration)`
- `Error (throwMaybeM)`
- `Grammar.Parser.GCase (VerbKey (DirectionalStimulusKey))`
- `Lens.Micro.Platform (over, use, view)`
- `Model.Core (ActionMaps, AgentMap, DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF), WitnessContext (AgentWitnessContext), actionConsequence, actionMaps, agentActionManagement, agentDescription, agentLocationMap, agentMap, agentShortName, getAgentMap, getGIDToDataMap, sceneActionManagement, sceneAgents, sceneMap, world)`
- `Model.GID (GID)`
- `Model.RichText (toPlainText)`

Export: add `manageAgentStimulusProcess` to module exports.

---

## File 8: `sasha/src/Engine/Resolution/ActionManagement.hs`

### Changes

**Add `AgentWitnessContext` handler in `processWitnessEffects`:**

```haskell
processWitnessEffects witnessGid actorGid (AgentWitnessContext targetGid) = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  target <- throwMaybeM ("Agent not found: " <> pack (show targetGid))
              (lookup targetGid aMap)
  modifyAgentNarration witnessGid
    (over actionConsequence
      (<> [colored White (toPlainText (view agentShortName actor)
                          <> " looks at "
                          <> toPlainText (view agentShortName target) <> ".")]))
```

Follows the same pattern as `DirectedWitnessContext` handler.

**New import:** `WitnessContext (AgentWitnessContext)` — add to existing WitnessContext import.

---

## File 9: `sashamud-world/test/DSL/BuilderSpec.hs`

### Changes

**Add e2e test for "look at player":**

Two players in the scene. Player 1 sends "look at player2name". Player 1 gets player 2's description. Player 2 gets witness narration.

This requires importing and using `runPureComputation` / `runEvalFor` from the engine, plus constructing a GameState with two agents. Need to verify what's exported from `Engine.Simulation.SignalNetwork` before writing the test body. The test follows the same pattern as the existing "look at ball" e2e test (commit 6fca98f — locate and follow its structure).

Test outline:

```haskell
it "look at player: actor sees target description, witness sees narration" $ do
  -- Set up: gameState with two players in lobby
  -- Player 1 (GID X) sends "look at player2name"
  -- Run computation
  -- Player 1 narration: actionConsequence contains player 2's agentDescription
  -- Player 2 narration: actionConsequence contains "{player1} looks at {player2}."
```

---

## Files with NO changes

- **SashaMudWorld.hs** — existing `playerLookAtKey` on denizens serves as the target agent veto. No new DSA management entries needed.
- **DSL/Model/EDSL/SashaLambdaDSL.hs** — no new DSL constructors needed.
- **DSL/Builder.hs** — no new interpretation needed.
- **ConstraintRefinement/Actions.hs** — existing `lookAtF` works for agent path veto.
- **Engine/ActionDiscovery/Protocol.hs** — agent path uses Protocol exports (`fetchAction`, `mkEffectKey`, `noGIDError`) but doesn't add a new ActionProtocol instance.
- **Engine/ActionDiscovery/Instances.hs** — agent path is a separate flow in Look.hs.
- **Engine/Resolution/Perception.hs** — existing `modifyAgentNarration` used as-is.
- **sasha-grammar.cabal** — no new modules.
- **sasha.cabal** — no new modules.

---

## Why the existing world wiring works for agents

The denizen template already gets `DSAManagementKey dsaLook playerLookAtGID` via `playerBehavior denizen playerLookAtKey`. So every player's `_agentActionManagement` has an entry for the look-at verb pointing to `lookAtF = DirectionalStimulusF processActionOutcomeRegistry`.

When player A looks at player B:
- **Player A's veto:** `lookupDirectionalStimulus dsaLook (view agentActionManagement actorAgent)` -> `playerLookAtGID` -> `lookAtF` -> `DirectionalStimulusF` -> allows
- **Target B's veto:** `lookupDirectionalStimulus dsaLook (view agentActionManagement targetAgent)` -> same `playerLookAtGID` -> same `lookAtF` -> allows
- **Scene's veto:** `lookupDirectionalStimulus dsaLook (view sceneActionManagement scene)` -> `sceneLookAtGID` -> `lookAtF` -> allows

All three allow. `processActionOutcomeRegistry` fires for each key but finds no linked world outcomes -> no-ops. Then the agent path renders B's `agentDescription` directly.

To veto being looked at, a future feature would set a specific agent's DSA entry to `lookAtDeniedF = DirectionalNoStimulusF processActionOutcomeRegistry` (already in ConstraintRefinement.Actions).

---

## Execution order

1. File 1 (Lexer) + File 4 (lexer test) — build sasha-grammar
2. File 2 (Model) + File 3 (Rules) — build sasha-grammar
3. File 5 (Core) — build sasha (types only)
4. File 6 (General) + File 7 (Look) + File 8 (ActionManagement) — build sasha
5. File 9 (e2e test) — build sashamud-world tests
