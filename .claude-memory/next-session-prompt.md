# Next Session Prompt

Paste this after /clear:

---

We are continuing commit 2 ("look" — first player-interactive content) for sashamud.

Read `/home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md` first. Then read the plan at `/home/mlitchard/.claude/plans/replicated-dreaming-shell.md`.

## What's done
- sasha-grammar: Earley parser, lexer, "look" parses to `Sentence (Imperative (StimulusVerbPhrase (ImplicitStimulusVerb (ImplicitStimulusVerb LOOK))))`
- All commit 1 infrastructure: server, WebSocket, Rhine pipeline (heartbeat + ping/pong), DSL (lobby scene), Nix

## What we're building
Player types "look" → sees lobby description + "Also here: {names}". Other players see "{name} looks around."

## The plan has 5 steps (each passes nix flake check):
0. Consolidate Mappings.hs into Core.hs
1. Model type cluster in Core.hs (GameComputation, ImplicitStimulusF, ActionMaps, ActionManagement, ActionEffectKey, registries, evaluator)
2. DSL GADT constructors (DeclareImplicitStimulusGID, CreateISAManagement, CreateImplicitStimulusEffect) + wireLook smart constructor
3. Engine (youSeeM, evaluator, runComputation (lifts GameComputation into pipeline, like old code's transformToIO))
4. Lobby wiring + Rhine integration + environmental narration

## Critical design points
- GameState PERSISTS across turns — carries world state (agents, scenes, objects)
- Each turn: existing GameState provides the foundation, effect contributes on top of it
- New GameState = existing state + contributions from the effect
- Narration extracted, delivered, cleared for next turn — world state carries forward
- Effects contribute pieces to GameState — they are part of the building computation
- Old code reference: sasha-engine/src/TopLevel.hs runGameWithInput (lines 123-149)
- Type cluster is interdependent: ActionManagement (ISAManagementKey verb GID) → ActionMaps (ImplicitStimulusMap) → ImplicitStimulusF (carries ActionEffectKeyF) → GameComputation
- DSL constructors are small composable pieces from old code — not monolithic
- Old code reference: /home/mlitchard/gitlab/sasha/ (patterns, not gospel)
- IX reference: /home/mlitchard/github/ix/src/IX/Reactive/EventNetwork.hs

Review the plan, then let's start with step 0.
