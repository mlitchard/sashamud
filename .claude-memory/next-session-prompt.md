# Next Session Prompt

Paste this after /clear:

---

We are continuing commit 2 ("look" — first player-interactive content) for sashamud.

Read `/home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md` first. Then read the plan at `/home/mlitchard/.claude/plans/replicated-dreaming-shell.md`.

## What's done
- sasha-grammar: Earley parser, lexer, "look" parses to `Sentence (Imperative (StimulusVerbPhrase (ImplicitStimulusVerb (ImplicitStimulusVerb LOOK))))`
- All commit 1 infrastructure: server, WebSocket, Rhine pipeline (heartbeat + ping/pong), DSL (lobby scene), Nix
- **Steps 0-2a DONE:** Full type cluster in Core.hs. NarrationMap, WitnessGenerate, WitnessFilter, WitnessEffect, WitnessMap added.
_presenceListing on Narration, _ctxWitnessMap on ComputationContext. GameState has _world + _narrationMap
(no _evaluation — arrives in Step 3c with real Evaluator). JSON roundtrip tests with QuickCheck (checkJSON pattern from quux).
- `nix flake check` passes.

## What we're building
Player types "look" → sees "You look around." + lobby description + "Also here: {names}". Other players see "{name} looks around."

## Next: Step 2b (DSL GADT constructors)

The plan has the detailed implementation. Read it before starting.

**Step 2b — File:** `sasha/src/DSL/Model/EDSL/SashaLambdaDSL.hs`

Add GADT constructors + smart constructors:
- `DeclareImplicitStimulusGID :: ImplicitStimulusF → SashaLambdaDSL (GID ImplicitStimulusF)`
- `SceneBehavior :: GID Scene → ActionManagement → SashaLambdaDSL ()`
- `CreateWorldOutcome :: ActionEffectKey → WorldOutcome → SashaLambdaDSL ()`
- `RegisterWitness :: ActionEffectKey → WitnessEffect → SashaLambdaDSL ()`

Study the old DSL at `/home/mlitchard/gitlab/sasha/sasha-dsl/src/Model/EDSL/SashaLambdaDSL.hs`
BEFORE writing anything. The GADT pattern, smart constructor naming, and export style must match.

## Key lesson from this session
ALWAYS study old code (sasha, quux/server, ix) BEFORE writing ANY pattern.
Do not guess. Every time you skip this step you create round trips of errors that
cost the user time. The instructions exist for a reason — follow them.
