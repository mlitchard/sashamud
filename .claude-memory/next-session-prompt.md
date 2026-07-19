# Next Task: Implement "look at <playername>"

## Step One
study the plan in /home/mlitchard/gitlab/sashamud/.claude-plans/look-at-player.md
## Context
"look at ball" (DirectionalStimulusVerb for objects) is complete and passing e2e tests including witness narration. The next task is "look at <playername>" — the agent path.

## What exists now
- Grammar: "look at ball" parses via `DirectStimulusVerbPhrase DirectionalStimulusVerb DirectionalStimulusNounPhrase` — object path
- Player names: `PlayerNameVAL` newtype in `Server/Validator.hs`, validated text
- Agent `_agentShortName` is `RichText`, set from player name text at join time via `defaultDenizen`
- Agents carry `_agentActionManagement :: ActionManagementFunctions` — can hold `DSAManagementKey` entries for veto
- ActionProtocol DirectionalStimulusF in `Engine/ActionDiscovery/Instances.hs`: object path only
- Witness system: `processWitnessEffects` dispatches on `WitnessContext`, exhaustive

## Design (user-approved)
- `Lexeme` gets a `PLAYERNAME Text` constructor — the lexer fallback. Known tokens (LOOK, AT, BALL, FLOOR) match first; any unrecognized word becomes `PLAYERNAME <the text>`
- `StimulusVerbPhrase` gets a NEW constructor carrying `PlayerNameVAL` — player-targeted look parse result
- Resolution in ActionManagement at runtime: look up `PlayerNameVAL` against agents in the current scene by iterating `sceneAgents` and matching `agentShortName`
- Agent path is a 3-way veto: player + target agent + scene. The target agent's `_agentActionManagement` can hold a `DSAManagementKey` that points to `DirectionalNoStimulusF` to veto being looked at. Same shape as the object path
- On success: render the target agent's `_agentDescription`
- Witness narration: "{actor} looks at {target player}."

## Steps to implement
1. Lexer: add `PLAYERNAME Text` constructor to `Lexeme`, add fallback term that catches unrecognized words
2. Grammar: wire `PLAYERNAME` through the parser — new noun type or extend existing, new `StimulusVerbPhrase` constructor
3. Evaluator: dispatch the new constructor
4. ActionManagement: resolve `PlayerNameVAL` against scene agents, 3-way veto (player + target agent + scene), render agent description
5. WitnessContext: add a constructor for agent-directed look
6. DSL/World: wire `DSAManagementKey` onto the denizen template so target agents participate in the veto chain
7. E2E test: two players, player 1 sends "look at <player2name>", gets player 2's description

## Key detail
`PLAYERNAME Text` on `Lexeme` changes the deriving — `Lexeme` currently derives `Bounded, Enum` which won't work with a `Text` field.
Those derivations may need removing or the Arbitrary instance needs updating. Check what breaks.

## Old code references
- Agent path: `sasha-engine/src/ActionDiscovery/Instances.hs:511-525`
- `validateObjectLook`: `sasha-engine/src/ActionDiscovery/Instances.hs:535-555`
- Agent semantic map: `sasha-core/src/Model/Core.hs:1215`
