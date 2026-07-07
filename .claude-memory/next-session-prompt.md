# Next Session Prompt

Paste this after /clear:

---

We are continuing commit 2 ("look" — first player-interactive content) for sashamud.

Read `/home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md` first. Then read the plan at `/home/mlitchard/.claude/plans/replicated-dreaming-shell.md`.

## What's done
- sasha-grammar: Earley parser, lexer, "look" parses to `Sentence (Imperative (StimulusVerbPhrase (ImplicitStimulusVerb (ImplicitStimulusVerb LOOK))))`
- All commit 1 infrastructure: server, WebSocket, Rhine pipeline (heartbeat + ping/pong), DSL (lobby scene), Nix
- **Steps 0-1 DONE:** Mappings.hs consolidated into Core.hs. All stubs replaced with real types. Full type cluster in place.
- **Core.hs has stale edits** from design discussion — WorldOutcome has incorrect WitnessEffect WitnessKey constructor, exports reference undefined types. Step 2a fixes these.

## What we're building
Player types "look" → sees "You look around." + lobby description + "Also here: {names}". Other players see "{name} looks around."

## Next: Step 2a (Core.hs witness types + NarrationMap + GameState refactor)

The plan has a detailed step-by-step implementation plan starting at Step 2a. Each step passes `nix flake check`.

## Design

### Witness system (separate effect)
- WitnessEffect (WitnessGenerate + WitnessFilter) lives in WitnessMap in PossibilityGraph, keyed by ActionEffectKey
- WitnessMap is the single source of truth for which actions have witness effects. WorldOutcome does not participate.
- Effect processor checks WitnessMap for each ActionEffectKey it processes. If present, runs generate with actor GID, runs filter per witness.
- WitnessGenerate produces text, WitnessFilter transforms per-witness (default: identity, stealth revisited later)

### NarrationMap (per-player routing)
- `NarrationMap = Map (GID Agent) Narration` — each player gets their own Narration
- Routing (who sees what) is NarrationMap's concern
- Content structure (playerAction → consequence → epilogue) is Narration's concern — orthogonal
- GameState holds NarrationMap instead of Narration

### Narration has four fields
- `_playerAction` — actor's action ("You look around.")
- `_actionConsequence` — result (scene description)
- `_presenceListing` — "Also here: PlayerB, PlayerC"
- `_actionEpilogue` — post-action notes
- Rendering order: playerAction → actionConsequence → presenceListing → actionEpilogue

### GameState Construction
- GameState is reconstructed each tick from current GameState + player input
- Effects inhabit GameState via dispatch tables (ActionManagementFunctions) on entities. The game world carries the effect configuration.
- Evaluator is the parser/dispatcher: text → scene dispatch table → GID → PossibilityGraph → effect function
- Effect functions live in PossibilityGraph (ComputationContext). Dispatch tables live on entities in GameState.
- Current GameState is input to next tick. Registries and dispatch tables carry forward. Narration is ephemeral.

### Actor GID
- Passed explicitly: pipeline → evaluator → effect functions → witness generate

### ComputationContext
- `_ctxPossibilityGraph :: PossibilityGraph`
- `_ctxWitnessMap :: WitnessMap`

Review the plan (especially the Implementation Plan section), then let's start with Step 2a.
