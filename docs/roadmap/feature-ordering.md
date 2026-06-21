# Feature Ordering: Commits 2-23

Conforms to: [monorepo-redesign.md](../monorepo-redesign.md) (living document, subject to correction)

Builds on: [commit-01-working-mud.md](commit-01-working-mud.md) (player login and heartbeat)

Adapted from: [feature-ordering.md](../../attic/docs/commits/feature-ordering.md) (old 5-repo layout, commits 1-22)

Commit 1 ships the complete pipeline: login, heartbeat (game content via
GameState), DSL (lobby), Rhine engine (PlayerTick + HeartbeatTick), TypeScript
client, Caddy, Nix. Commit 2 adds player-interactive content ("look") with
parser, action resolution, and GameEvent behaviors. Each subsequent commit
adds one capability to a system that already works. The reader never sees
dead code.

All four packages live in one monorepo — no cross-repo pinning needed.

**Every commit has tests.** Tests execute during `nix flake check`. Test
stanzas use `executable`, not `test-suite`. Tests use hspec-discover.
No commit ships without tests that verify the capability it introduces.

---

## Commit 2: "look" — First Player-Interactive Content

**Packages:** sasha-grammar, sasha-vocabulary, sasha (Model/, DSL/, Engine/, Server/), sashamud-world

Parser, action resolution, and GameEvent behaviors added to the pipeline
that commit 1 established. DSL grows from scene-only to action registration.

- Minimal parser: "look" only (single Earley rule, ImplicitStimulusVerbPhrase)
- sasha-vocabulary: lookLexeme
- Minimal DSL: HasPerception with ImplicitStimulusF instance only
- `look` smart constructor in DSL.Vocabulary.Wiring registers action + GameEvent behavior
- GameComputation with hoistComputation bridge (natural transformation)
- Action resolution: ActionProtocol, evaluator, processActionOutcomeRegistry
- PlayerTick clock added to Rhine pipeline (drains commands, runs engine, routes narration)
- GameEventClock (EventClock): fires on GameEvent, `gameEventSF` Behavior responds
- GameEvent type (ActionCompleted constructor)
- GameEventRegistry in PossibilityGraph (immutable lookup: ActionEffectKey -> Behavior update functions)
- One room (lobby), "look" shows description + "Also here: Bar"
- GameEvent behavior: other players see "{name} looks around." via environmental narration

**Tests:** JSON roundtrip (core types), lexer/parser roundtrip ("look"), engine
computation (look produces narration), GameEvent behavior fires (environmental
narration for other agents), Rhine pipeline integration (command in, narration out)

**Teaches:** the full game pipeline end to end — parser, DSL, engine,
reactive pipeline, Events and Behaviors, all wired

---

## Commit 3: Chat Commands

**Packages:** sasha (Server/) only

- /say, /tell, /shout, /me, /list, /help, /quit
- Server-layer only — engine never sees these

**Tests:** chat commands route to correct clients, unknown commands produce
error, /quit disconnects

**Teaches:** server routes vs engine produces — the boundary in action

---

## Commit 4: Demo Accounts + Agent Lifecycle

**Packages:** sasha (Server/), sashamud-world

- Login as "demo" -> "demo-dude-X", ephemeral, no DB state writes
- Agent cleanup on disconnect (remove from World agentMap, remove from scene)

**Tests:** demo login creates agent in lobby, disconnect removes agent from scene
and agentMap, multiple demo logins produce unique names

**Teaches:** dynamic agent creation/destruction, ephemeral vs persistent state

---

## Commit 5: PostgreSQL Persistence

**Packages:** sasha (Server/Persist/, Engine/Simulation/Clocks.hs)

- PersistenceTick (15-minute Rhine clock)
- World persistence: normalized tables with GID domains, not a serialized blob
- accounts table, numbered SQL migrations run at startup
- Load World from DB on startup, reconstruct GameState runtime fields

**Tests:** save/load roundtrip (World survives persistence cycle), migrations run
idempotently, GameState runtime fields reconstructed correctly from loaded World

**From this commit forward:** every commit that adds or changes persistent types
includes a numbered SQL migration and a persistence roundtrip test. The World
must survive save/load with the new data.

**Teaches:** what gets saved (World) vs what gets reconstructed (everything else)

---

## Commit 6: Objects — Red Ball and Blue Ball

**Packages:** sasha (Model/Core/Object.hs, DSL/, Engine/Resolution/), sashamud-world

- Two balls in lobby (red ball, blue ball) — first objects in the world
- Object type introduced (Model/Core/Object.hs)
- DirectionalStimulusF instance added to HasPerception
- NounPhrase parsing: SimpleNounPhrase, DescriptiveNounPhrase, DescriptiveNounPhraseDet
- Adjectives in vocabulary (red, blue)
- "look at ball" -> disambiguation placeholder (next commit)
- "look at red ball" / "look at blue ball" -> resolves cleanly
- Environmental narration: other players see "{name} looks at the red ball"
- Migration: objects table, object spatial relationships, object-to-scene mapping

**Tests:** parser resolves "look at red ball" to correct object GID,
DirectionalStimulusF fires correct narration, GameEvent behavior produces
"{name} looks at the red ball", objects persist and load correctly

**Teaches:** object registration, noun resolution, directional perception

---

## Commit 7: Disambiguation

**Packages:** sasha (Engine/Resolution/)

- "look at ball" with two balls present triggers disambiguation ("Which ball?")
- buildDisambiguationOptions, fireDisambiguation wired
- Player selects, action resolves
- AmbiguousObjects / AmbiguousEntities path fully exercised

**Tests:** ambiguous noun triggers disambiguation prompt, selection resolves
to correct object, unambiguous nouns skip disambiguation

**Teaches:** the engine's disambiguation infrastructure end-to-end

---

## Commit 8: Get/Drop

**Packages:** sasha (DSL/Internal/HasEffect.hs, Engine/Resolution/), sashamud-world

- AcquisitionF, DivestmentF smart constructors added as plain functions in HasEffect.hs
- "get ball" (ambiguous) -> disambiguation -> "get red ball" resolves
- "drop ball" — DivestmentF (simple, to floor)
- AcquisitionF, spatial relationships (scene -> inventory)
- Inventory system
- Environmental narration: "{name} picks up the red ball" / "{name} drops the red ball"

**Tests:** get moves object from scene to inventory (spatial relationship changes),
drop moves from inventory to floor, environmental narration fires for both,
spatial relationship changes persist (save/load roundtrip after get/drop)

**Teaches:** acquisition, divestment, spatial relationship changes

---

## Commit 9: Throw/Give

**Packages:** sasha (Engine/Resolution/, Server/), sashamud-world

- "throw ball to foo" — GLOBAL, MUD-wide delivery to any player's inventory
  - GlobalDivestmentVerbPhrase
  - Resolves agent by name across all sessions
  - Preposition "to" -> global scope
- "throw ball at foo" / "give ball to foo" — LOCAL, same room only
  - Standard DivestmentF with agent target
  - Preposition "at" -> local scope
- Both need dynamic player name resolution (against connected agents)

**Tests:** "throw ball to foo" delivers globally, "throw ball at foo" requires
same room, agent name resolution finds connected players

**Teaches:** preposition-determined scope, global vs local targeting

---

## Commit 10: Light Switch

**Packages:** sasha (Engine/Resolution/), sashamud-world

- "turn light on" / "turn light off" (ToggleVerb + verb phrase)
- Visibility gates GameEvent behaviors — can't perceive actions in the dark
- Effect cluster: lights off -> denied look, denied environmental narration
- State-dependent action availability via slot swaps
- Migration: light switch object, effect cluster state persisted via action management

**Tests:** light off denies look (slot swap verified), light on restores look,
environmental narration blocked in dark room, GameEvent behavior fires in lit room,
light state persists (save/load roundtrip preserves on/off via GID mapping)

**Teaches:** state as GID mappings, slot swaps, visibility gating

---

## Commit 11: Postural Actions — Sit/Stand + Open/Close Eyes

**Packages:** sasha (DSL/Internal/HasAccess.hs, Engine/Resolution/), sashamud-world

- HasAccess.hs introduced — HasAccess class with SomaticAccessF instance (open/close polymorphism)
- PosturalF: sit and stand (player body state) — plain functions in HasEffect.hs
- SomaticAccessF: open eyes, close eyes (sensory gating) — open/close via HasAccess, wear/remove as plain functions
- Denied action chains: eyes closed -> can't look; sitting -> can't get
- Slot swaps on player entity (same mechanism as commit 10, but player-scoped)
- These are GENERAL capabilities available in any room
- Environmental narration: "{name} stands up" / "{name} opens their eyes"

**Tests:** eyes closed denies look, standing enables get, chained denial
(eyes closed -> stand denied -> get denied), environmental narration fires for postural
changes, postural state persists (save/load roundtrip preserves sit/stand
and eyes open/closed)

**Teaches:** player-scoped slot swaps, chained denials, somatic vs postural

---

## Commit 12: Readable Objects — TransitiveStimulusF

**Packages:** sasha (Engine/Resolution/), sashamud-world

- Sign in lobby: "read sign" introduces TransitiveStimulusF action type — plain function in HasEffect.hs
- TransitiveStimulusVerb in grammar ("read", "examine")
- Object builder pattern: named + described + andThen + overlayReadable
- Environmental narration: "{name} reads the sign"

**Tests:** "read sign" parses and produces narration, TransitiveStimulusF fires
correct effects, environmental narration fires for reading, new objects persist
(save/load roundtrip with sign)

**Teaches:** new action type integration, object builder pattern

---

## Commit 13: Movement — Cardinal Directions

**Packages:** sasha (Engine/Resolution/), sashamud-world

- CardinalMovementF action type — plain function in HasEffect.hs
- Two rooms: lobby + corridor (east of lobby)
- "go east" / "east" / "e" all parse
- Denied movement: "You can't go that way."
- Departure/arrival narration through effect system (NOT server)
- Environmental narration: "{name} heads east" (departure) / "{name} arrives from the west" (arrival)
- Scene description on arrival via processNarrationEffect LookNarration
- youSeeM lists other agents: "Also here: Bar"
- Scene adjacency graph constructed here (first multi-room)
- Migration: corridor scene, scene adjacency graph, cardinal movement action management

**Tests:** "go east" moves agent to corridor, denied direction produces error
narration, departure/arrival environmental narration fires for agents in old/new scene,
scene adjacency graph correct, agent scene location persists (save/load
roundtrip after movement), new scene persists

**Teaches:** movement, multi-room, departure/arrival narration via effects

---

## Commit 14: Containers — Spatial Hierarchy

**Packages:** sasha (DSL/, Engine/Resolution/), sashamud-world

- ContainerAccessF: "open bag" opens a container — ContainerAccessF instance added to HasAccess (open/close polymorphism)
- DirectionalStimulusContainerF: "look in bag" shows container contents — instance added to HasPerception
- "get ball from bag" — spatial graph traversal for acquisition
- Bag object in lobby as teaching example
- Spatial relationships: ContainedIn, Contains
- Builds on AcquisitionF (commit 8) + SomaticAccessF conceptually

**Tests:** "open bag" changes container state, "look in bag" shows contents,
"get ball from bag" traverses spatial graph, spatial relationships
(ContainedIn, Contains) correct after operations, container hierarchy
persists (save/load roundtrip with nested spatial relationships)

**Teaches:** spatial hierarchy, container mechanics, graph traversal

---

## Commit 15: Static Agent — Brewster (Tea-O-Matic)

**Packages:** sasha (Model/, Server/), sashamud-world

- First agent WITHOUT a session
- HasSession typeclass introduced HERE — divides dynamic agents (players) from static agents (NPCs)
- Brewster: sentient tea machine in the lobby — BrightCyan bold text
- RogativeF: "ask brewster for tea" -> gives tea to player — plain function in HasEffect.hs
- Demonstrates HasSession divide:
  - Brewster: no session, no message routing, no state persistence
  - Players: have sessions, receive messages, state saved
- Students see: agent registration, agent actions, the dynamic/static split

**Tests:** Brewster has no session, "ask brewster for tea" produces tea in
inventory, RogativeF fires correctly, static agent persists across player
connections, static agent persists in DB (save/load roundtrip with Brewster,
migration for agent kind)

**Teaches:** HasSession boundary, static agents, NPC interaction

---

## Commit 16: Arcade Room + Locker

**Packages:** sasha (Engine/Resolution/), sashamud-world

- Arcade room added (east of corridor)
- Sign in arcade (readable — reuses TransitiveStimulusF from commit 12)
- ControlF: "start sashademo" — ungated for now, just works — plain function in HasEffect.hs
- Arcade is the entry point to the demo
- Locker: per-player inventory stash — each player sees only their own locker
  - "look in locker" — shows stashed items
  - "get foo from locker" / "get all from locker" — retrieve items
  - "start sashademo" stashes current inventory into locker
  - On demo exit, player retrieves from locker
- **Per-agent scene state** (`_sceneAgentOverlays`) introduced HERE

**Tests:** "start sashademo" stashes inventory into locker, locker contents are
per-player, per-agent scene overlay applied correctly, ControlF fires,
per-agent scene overlays persist (save/load roundtrip), locker contents persist,
migration for arcade scene + per-agent overlay tables

**Design constraint:** all commits 2-15 must NOT make choices that conflict with per-agent scene state

**Teaches:** ControlF, per-agent scene state, inventory stashing

---

## Commit 17: Sequence Advancement System

**Packages:** sasha (Model/, Engine/Simulation/, Engine/Resolution/)

- NewActiveSequence, SequenceCategory (HeartbeatSequence, AgentSequence, WorldSequence)
- SequenceTarget (PlayerTarget, SceneTarget, AgentProximityTarget)
- advanceSequencesByCategory, frame counters, sequence lifecycle
- AgentTick (30s) and WorldTick (45s) Rhine clocks wired into pipeline
- Server routes sequence narration by target type
- Simple demonstration sequence in lobby (e.g., ambient narration on WorldTick)

**Tests:** sequence advances on correct tick category, frame effects fire in order,
cancelled sequences stop advancing, sequence narration routes to correct target,
active sequences persist (save/load roundtrip reconstructs sequence state
at correct frame)

**Teaches:** tick-driven autonomous behavior — the engine does things without player input

---

## Commit 18: Demo Layer 1 — Bedroom Basics + Trixie (Attic Lesson One)

**Packages:** sashamud-world

- Bedroom scene created inside the demo
- Objects: bed, chair, door, floor, table, intercom
- All actions start DENIED (demo begins with eyes closed in bedroom)
- Trixie registered as invisible static agent in bedroom (and pod room when it exists)
  - No "Also here: Trixie" — invisible to room descriptions
  - Denied interactions with sass: "look at trixie", "get trixie" — GLaDOS grandniece personality
  - 9-frame event-driven sequence: gate clears trigger next gate narration
  - ALL snarky/guidance denied narrations are Trixie-voiced
  - Introduces Brewster to the player ("My girl Brewster is right there on the table...")
  - Yellow text
- Lenny — NOT in bedroom, presence via intercom only
  - Intercom: lookable, player use denied with flavor text
  - Lenny responses scheduled by Trixie frame effects (one tick delay)
  - Frame 9 (final): Lenny clears all remaining gates, moves player to pod room
- Brewster (Tea-O-Matic) on bedroom table — 5-frame nag sequence, BrightCyan bold
  - Brewster leads, Trixie calls back one tick later

**Tests:** bedroom scene loads with all objects, all actions start denied,
Trixie sequence advances through 9 frames, Lenny frame 9 clears gates
and moves player, demo scene content persists (save/load roundtrip with
bedroom, all objects, agents)

**Teaches:** content authoring — adding a room with objects and agents, effect wiring

---

## Commit 19: Demo Layer 2 — Open Eyes, Perception (Attic Lesson Two)

**Packages:** sashamud-world

- Wire open/close eyes into demo bedroom's effect cluster
- Opening eyes enables look + look at (slot fills swap GIDs)
- Chair has lookable Success (shows chair description)
- Table has lookable Success (student assignment target)
- Effect wiring: playerOpenEyesSlots + sceneOpenEyesSlots

**Tests:** eyes closed denies look in demo context, opening eyes enables
look + look at, chair/table descriptions visible after eyes open, slot
swaps verified on player and scene, demo state survives persistence
(save/load roundtrip mid-demo preserves eye state)

**Teaches:** state transitions via slot swaps, player vs scene GID separation

---

## Commit 20: Demo Layer 3 — Stand Up, Get Objects (Attic Lesson Three)

**Packages:** sashamud-world

- Standing enables get (slot fills on player + objects)
- Robe on chair (SupportedBy spatial relationship), lamp on table
- "get robe" works after standing -> AcquisitionF
- "get lamp" is student assignment — lamp is needed in the pod room (commit 22)
- Effect wiring: playerStandSlots + sceneStandSlots + acquisition slot fills

**Tests:** standing enables get, "get robe" acquires robe from chair, spatial
relationship changes (SupportedBy -> Inventory), slot fills verified,
mid-demo inventory persists (save/load roundtrip after acquiring robe/lamp)

**Teaches:** chained state transitions (eyes -> posture -> acquisition)

---

## Commit 21: Demo Layer 4 — Robe, Pocket, Pill (Containers + Consumption)

**Packages:** sashamud-world

- Robe has a pocket (container) — ContainedIn spatial relationship
- Pill inside pocket — "get pill from pocket"
- "wear robe" — SomaticAccessF applied to clothing
- ConsumptionF: "take pill" (consumed, not just acquired) — plain function in HasEffect.hs
- Effect cluster: taking pill enables something downstream
- Demonstrates containers (commit 14 infra) in a puzzle context

**Tests:** "get pill from pocket" traverses container, "take pill" consumes
(removed from spatial map), consumption effect cluster fires downstream
state change, consumption persists (consumed object stays removed after
save/load roundtrip)

**Teaches:** containers in practice, consumption, downstream state gating

---

## Commit 22: Demo Layer 5 — Pod Room + Puzzle Mechanics

**Packages:** sasha (Engine/Resolution/), sashamud-world

- Pod room added (second demo room, through bedroom door portal)
- PortalAccessF introduced here (bedroom door) — PortalAccessF instance added to HasAccess (open/close polymorphism)
- Pod room is DARK — visibility-gated, all perception/manipulation denied without light
- Lamp from commit 20 required
- Objects: ladder, latch, hatch, button
  - Ladder: furniture, lookable, supports the latch and hatch
  - Latch: liftDenied (initial) -> liftSuccess (after Lenny presses button) — ManipulationF Liftable
  - Hatch: lookable only — game ends when latch is lifted
  - Button: always pressDenied for player — only Lenny can reach it
- ManipulationF introduced here (lift, press) — plain functions in HasEffect.hs
- Lenny present as agent — "ask lenny for help" -> he presses button -> latch unlockable
- Lifting latch = demo victory, player returns to arcade
- Demo exit: scene transition back to arcade, locker retrieval, inventory swap

**Tests:** portal opens and transfers agent, dark room denies all perception,
lamp enables perception in dark room, Lenny button press unlocks latch,
latch lift triggers demo exit, inventory swap on exit,
pod room content persists (save/load roundtrip with portal, puzzle objects, Lenny),
migration for pod room scene + portal relationships

**Teaches:** portal mechanics, visibility gating with portable light, NPC-gated puzzles

---

## Commit 23: Trixie Gate — Capstone

**Packages:** sashamud-world

- Per-agent gate progression (SceneAgentKey from per-agent scene state)
- Three-stage denial chain: polite -> sardonic -> force-start
- "start sashademo" now gated until sign is read
- First demonstration of per-agent scene state (different players at different gate stages)
- One-shot arrival narration (Trixie introduction on first corridor->arcade entry)
- Player has already MET Trixie as narrator inside the demo — gate retroactively makes sense

**Tests:** gate progression persists per-agent, three denial stages fire in order,
sign read clears gate, one-shot arrival narration fires once and only once,
different players at different gate stages simultaneously,
gate state persists (save/load roundtrip preserves per-agent gate progression)

**Teaches:** per-agent scene state in practice, multi-stage gating, narrative payoff

---

## Unsequenced (post-23 or insert points TBD)

- Test infrastructure (Selenium + generated TS client)
- Telemetry viewports (AnalysisData, F4 parser, F5 state)
- Web client (TypeScript browser app)
- Admin tooling (admin nix app, /admin endpoints, account CRUD)
- Audit trail (player_sessions, player_events, command logging)
- AI-driven robot agents
- InterrogativeF ("ask X about Y") — plain function in HasEffect.hs
- ComitativeF ("empathize with X") — plain function in HasEffect.hs (west zone puzzle)
- DirectedImperativeF ("lenny, pull bust") — plain function in HasEffect.hs (west zone puzzle)
