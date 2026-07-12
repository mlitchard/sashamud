# Blog Post Prompt: "What Happens When You Type 'look' — FRP in a Multiplayer MUD"

## Purpose
Organize a sashamud blog post that walks the reader through the full pipeline from two players logging in to one typing
`look` — and the other *witnessing* it. The technical focus is Rhine, FRP signal processing, and why this architecture makes
multiplayer tractable.

## Audience
Haskell-curious developers, FRP enthusiasts, game engine people. Assume comfort with types and pure functions.
Don't assume Rhine or MUD knowledge.

## Narrative Arc

### Act 1: Two Players Walk Into a Lobby
- The setting: two browser clients, one server, one game world
- Login arrives over WebSocket — this is **server territory** (AppCtx, MVars, TChans)
- Server state is irreducibly concurrent: connections arrive whenever,
disconnect without warning, multiple writers touching session maps
- Key idea to land: the architecture doesn't try to tame the concurrency — it **quarantines** it
- Introduce the boundary: server state (async, multi-writer) vs game state (sequential, one writer)

### Act 2: The Rhine Backbone
- What Rhine gives you: signal functions composed with `>->`, clocked by real time, running in a monad stack
- The PlayerTick chain — one sequential pipeline, one clock:
  `deliverNarrationSF >-> processLeavesSF >-> processJoinsSF >-> executeJoinsSF >-> gatherInputSF >-> processInputSF`
- Each SF does one job, passes the world downstream. No shared mutable state between stages — the chain IS the ordering guarantee
- GameState rides in `AccumT (Last GameState)` behind the RhineM newtype — explain what AccumT buys you vs StateT
(Rhine koans say StateT cannot parallelize with `|@|`; AccumT can, monoidal accumulation)
- `Last GameState`: newer wins, `Last Nothing` = no contribution (heartbeat ticks, liftIO),
no Semigroup/Monoid needed on GameState itself
- One writer for game state: the chain. Period. That's how you get determinism in a concurrent world

### Act 3: A Player Joins — Signal by Signal
- Walk through what happens tick-by-tick when Player A logs in:
  - `processJoinsSF`: reads acKnownPlayers once, detects new name, assigns a GID
  (atomicModifyIORef on acNextAgentId — counter lives in AppCtx, not the accumulator)
  - `executeJoinsSF`: runs the DSL-built `newUser` computation — places agent in lobby
  scene, announces "Player A has arrived." to everyone in the scene via NarrationMap, enqueues auto-look (`GameCommand "look"`)
  - Next tick: `deliverNarrationSF` drains NarrationMap — each player gets their narration routed by GID, then flushed
- Repeat for Player B joining — same pipeline, same machinery, now two agents in sceneAgents
- Key idea: the engine doesn't know what "joining" means beyond "run the registered computation."
  The DSL defined it; the engine executes registries

### Act 4: "look" — From Keystroke to Narration
- Player A types `look`. WebSocket delivers it. gatherInputSF drains the channel
- processInputSF: `lexify` (megaparsec) turns raw text into tokens, Earley parser produces a
`Sentence` — typed by parsing, not wrapping. Unverified input can't reach the parser by construction
- The evaluator: pure dispatch. `Sentence` pattern-matches to `StimulusVerbPhrase`,
- dispatches to `manageImplicitStimulusProcess`
- The registry walk: agent carries `ISAManagementKey verb (GID ImplicitStimulusF)`
- in its ActionManagementFunctions. Scene carries one too. Both resolve through PossibilityGraph's ActionMaps to the actual function
- The veto chain: `runActionProtocol` fires callbacks — player key first (no registry entry = silent no-op),
  then scene key (registered). ImplicitStimulusF wraps processActionEffects, which looks up WorldOutcomeRegistry by ActionEffectKey
- Two outcomes registered on that key:
  - `NarrationEffect LookNarration` — actor side: `youSeeM` writes room description + presence listing into Player A's Narration
  - `WitnessEffect LookNarration` — witness side: processWitnesses walks agentLocationMap -> sceneAgents,
     filters out actor, filters for Denizen, checks each witness's WitnessManagementKey, dispatches `witnessLookM` — Player B sees "Player A looks around."
- All narration lands in NarrationMap inside the one-writer chain. Next tick's deliverNarrationSF delivers it. Done

### Act 5: Why This Shape
- Capabilities as data, not code paths. The engine doesn't know what "look" is. Agents carry keys, keys point to GIDs,
- GIDs resolve through registries. To add stealth later: swap a GID. State IS which GIDs are mapped
- The DSL declares; the engine executes. World content is a library package (sashamud-world),
- separate from the engine (sasha). The next twenty verbs are just more registry entries
- One semantic datum, two renderings: LookNarration means "someone looked." Actor side renders "You look around." Witness side renders "Foo looks around." The NarrationComputation is the shared truth; the rendering is the perspective
- The engine got smaller as the game got bigger. Witness system added zero new pipeline stages — it hooked into existing WorldOutcome processing. That's how you know the shape was right

## Technical Diagrams to Consider
1. The quarantine boundary: server state (AppCtx) vs game state (AccumT) with the SF chain as the membrane
2. The PlayerTick chain as a pipeline diagram: SF boxes connected by >->, annotated with what each reads/writes
3. The registry resolution walk: ActionManagementFunctions -> GID -> ActionMaps -> function, with the veto chain branching
4. The witness discovery walk: actor -> scene -> sceneAgents -> filter -> WitnessManagementKey -> WitnessMap -> narration

## Code Snippets to Feature
- The PlayerTick chain composition (one line of >-> that tells the whole story)
- RhineM newtype and AccumT (Last GameState) — the trick that makes one-writer work
- processWitnesses — the witness walk, showing every lookup as a case with silent fallthrough
- The DSL wiring in SashaMudWorld.hs — declareWitnessGID, createWitnessManagement, playerBehavior,
- linkWorldOutcomeEffect — showing how world content is declared, not coded
- processInputSF bridge: lexify -> parseTokens -> eval -> unwrap -> add gs'
- (the whole text-to-world-change in one pipeline)

## Tone
Technical but warm. This is a devlog from someone who cares about the craft.
Explain the "why" before the "how." Let the architecture speak — don't oversell it,
just show the decisions and let the reader see why they compound.

## Length Target
~2500-3500 words. Long enough to walk the full pipeline with real code. Short enough that the narrative never stalls.
