# SashaMud Monorepo Architecture

Conforms to: [commit-01-working-mud.md](roadmap/commit-01-working-mud.md), [feature-ordering.md](roadmap/feature-ordering.md)

## Overview

SashaMud is organized as a monorepo with five cabal packages.

```
sasha-grammar ─── sasha-vocabulary
      \                /
         sasha
           |
      sashamud-world
           |
     sashamud-server
```

Each package exists because a different consumer needs a different subset of
the codebase.

---

## The Four Packages

### sasha-grammar — Language Foundation + Processing

The linguistic foundation. Contains the Lexeme alphabet, all parser types
Sentence, Imperative, verb/noun phrase types), NounKey, VerbKey, VocabConfig,
and the Earley + megaparsec parser engine. Everything about what players say
and how it gets parsed.

**Depends on:** base, Earley, megaparsec, text, hashable, relude, template-haskell, containers, unordered-containers

**Does not depend on:** GID, game state, Rhine, servant, or any world-model type.

**Why it exists:** Independent domain. The parser can be used standalone
for client-side validation or tooling. Grammar types are the linguistic foundation
that both vocabulary and the application import — without pulling in the game
engine, Rhine, or networking.

### sasha-vocabulary — Swappable Word Lists

Game-specific vocabulary. SashaMud's dictionary. A different game brings a
different vocabulary package.

**Depends on:** sasha-grammar (for Lexeme, VocabConfig types), template-haskell,
hashable

**Why it exists:** Swappability. A fantasy MUD creates `fantasy-vocabulary`
with its own words. Everything else stays the same.

### sasha — The Application

Engine, API, and server in one package. Contains the world-model types
(GID, GameState, Agent, Scene, Object, PossibilityGraph), the DSL for world
construction, the Rhine reactive dataflow graph, the Servant API, and the server.

**Depends on:** sasha-grammar, sasha-vocabulary, rhine, servant, servant-server,
servant-websockets, warp, stm, clay (Color only), aeson, aeson-typescript,
microlens-platform, mtl, containers

**Why it's one package:** Engine, API, and server always build together,
always deploy together, and no external consumer needs one without the others.

### sashamud-world — Game Content

The specific game world. Scenes, objects, agents, puzzles, narratives,
effect wiring. A different game world is a different package.

**Depends on:** sasha, sasha-grammar, sasha-vocabulary

### sashamud-server — Server Executable

The thin top-level package that wires the server to the game content.
Contains only the `sasha-server` executable (`Main.hs`), which imports
`startServer` from `sasha` and `gameState`/`possibilityGraph` from
`sashamud-world`. Future end-to-end tests live here.

**Depends on:** sasha, sashamud-world

**Why it exists:** The server executable needs both the engine (`sasha`)
and the game content (`sashamud-world`). Placing it in either package
creates a circular dependency. This package sits at the top of the
dependency tree, assembling the final application.

---

## Module Layout Convention

Every directory follows the pattern: top-level `Foo.hs` re-exports the public
API from `Foo/` directory. `Foo.hs` is what other modules import. Internal modules live in `Foo/`.

```
src/
  Foo.hs        -- re-exports public types and functions from Foo/
  Foo/
    Bar.hs      -- internal module, imported by Foo.hs
    Baz.hs      -- internal module, imported by Foo.hs
```

---

## Module Layout: sasha

Three concerns — Model, DSL, Engine — with clear separation between world
creation (DSL) and world runtime (Engine). Model defines the types both share.

```
sasha/src/
│
├── SashaPrelude.hs                  -- Custom prelude (NoImplicitPrelude enforced)
│
├── Model/                           -- SHARED TYPES (used by both DSL and Engine)
│   ├── Core.hs                      -- re-exports from Core/
│   ├── Core/
│   │   ├── GameState.hs             -- GameState, PossibilityGraph, GameEventRegistry
│   │   ├── Agent.hs                 -- Agent, AgentKind, AgentMap
│   │   ├── Scene.hs                 -- Scene
│   │   ├── Object.hs               -- Object (commit 6+)
│   │   ├── EntityKey.hs             -- EntityKey constructors
│   │   ├── Defaults.hs             -- defaultAgent, defaultScene, default action management
│   │   ├── Mappings.hs             -- ActionManagement types, ActionManagementFunctions
│   │   ├── GameEvent.hs            -- GameEvent, GameEventKey, GameEventRegistration
│   │   └── World.hs                -- World (agentMap, sceneMap, spatialRelationshipMap)
│   ├── GID.hs                       -- GID newtype (phantom-typed), role phantom
│   ├── Lens.hs                      -- makeLenses runs in each module; Lens.hs not needed
│   ├── RichText.hs                  -- RichText, StyledSpan, TextStyle (Clay.Color)
│   ├── WireProtocol.hs              -- WireMessage, CommandResponse, GameNarration, SystemMessage
│   └── RandomPool.hs               -- RNG stream types
│
├── Error.hs                         -- error combinators
│
├── DSL/                             -- WORLD CREATION (build phase)
│   ├── Builder.hs                   -- interpretDSL, WorldBuilder, runWorldBuilder
│   ├── Vocabulary.hs                -- buildScene, buildAgent, named, described, andThen
│   ├── Vocabulary/
│   │   └── Wiring.hs               -- Smart constructors: look (registers action + GameEvent behavior)
│   ├── Internal/
│   │   ├── HasPerception.hs         -- HasPerception class (commit 2: ImplicitStimulusF)
│   │   ├── HasAccess.hs             -- HasAccess class: open/close (commit 11: SomaticAccessF; later ContainerAccessF, PortalAccessF)
│   │   ├── HasEffect.hs             -- Plain function groups, NOT classes (PosturalF, ManipulationF, ControlF, AcquisitionF, DivestmentF, ConsumptionF, TransitiveStimulusF, RogativeF, InterrogativeF, ComitativeF, DirectedImperativeF, CardinalMovementF, SomaticAccessF wear/remove)
│   │   ├── HasAction.hs             -- declareAction
│   │   ├── EffectAlgebra.hs         -- action, triggers, on
│   │   ├── EffectCluster.hs         -- SlotFill, wireSlots
│   │   └── TypeMappings.hs          -- action type -> map lens
│   ├── Effects.hs                   -- narrate, narrateLook (WorldOutcome constructors)
│   └── Model/EDSL/
│       └── SashaLambdaDSL.hs        -- GADT DSL monad
│
├── ConstraintRefinement/
│   ├── Class.hs                     -- RefinableAction (allowed/denied constructors)
│   └── Actions.hs                   -- constraint functions (getF, standF, etc.)
│
├── Engine/                          -- WORLD RUNTIME (execution phase)
│   ├── Resolution/                  -- Action resolution (no Rhine, no IO)
│   │   ├── GameState.hs             -- modifySceneM, modifyAgentM, getAgentSceneM
│   │   ├── GameState/
│   │   │   ├── Perception.hs        -- youSeeM, scene description
│   │   │   ├── ActionOutcomes.hs    -- processActionOutcomeRegistry
│   │   │   ├── Processing.hs        -- processWithSystemEffects, toGameComputation
│   │   │   ├── ActionManagement.hs  -- effect processing
│   │   │   ├── AgentManagement.hs   -- NPC request processing
│   │   │   ├── EffectRegistry.hs    -- registry lookups
│   │   │   └── Spatial.hs           -- container traversal
│   │   ├── ActionDiscovery/
│   │   │   ├── Protocol.hs          -- ActionProtocol typeclass
│   │   │   ├── Instances.hs         -- protocol instances per action type
│   │   │   └── Percieve/
│   │   │       └── Look.hs          -- look action discovery
│   │   ├── Evaluators/
│   │   │   └── Player/
│   │   │       └── General.hs       -- eval :: Text -> GameComputation Identity ()
│   │   ├── TopLevel.hs              -- topLevel, defaultEvaluator
│   │   ├── Interface/
│   │   │   └── SceneNarration.hs    -- formatSceneDescription
│   │   └── Telemetry/
│   │       ├── Types.hs
│   │       ├── Snapshot.hs
│   │       └── Format.hs
│   │
│   └── Simulation/                  -- Rhine FRP network (the living world)
│       ├── GameLoop.hs              -- rhinePipeline, gameLoop
│       ├── Clocks.hs                -- PlayerTick, HeartbeatTick, GameEventClock, GameClock
│       ├── Monad.hs                 -- GameChan, RhineM, liftGameChan, emitGameEvent
│       ├── Bridge.hs                -- runComputation (hoistComputation bridge)
│       ├── Route.hs                 -- routeNarration, routeGameEventNarration, routeToClient
│       └── Sequences.hs            -- temporal sequence advancement
│
├── API/                             -- I/O contracts
│   ├── Types.hs                     -- GameCommand, Credentials, LoginResponse
│   ├── Routes.hs                    -- Servant API type (TypedWebSocket)
│   └── TSClient.hs                  -- TypeScript client codegen
│
└── Server/                          -- I/O binding
    ├── App.hs                       -- AppCtx (server concerns only — no GameState, no PossibilityGraph)
    ├── Server.hs                    -- startServer, hoistServerWithContext
    ├── GameWebSocket.hs             -- WebSocket handler, connection -> player agent creation
    ├── Session.hs                   -- session registry
    ├── Validator.hs                 -- input validation
    ├── Log.hs                       -- structured logging categories
    ├── Metrics.hs                   -- Prometheus
    └── Persist/                     -- (commit 5+)
        ├── Auth.hs                  -- PostgreSQL auth/authz
        └── GameSave.hs             -- PostgreSQL game state persistence
```

---

## Separation: World Creation vs World Runtime

### The Boundary

DSL modules produce data. Engine modules consume it. Model modules define
the types both share. DSL/ imports from Model/ only.
Engine/ imports from Model/ only. Neither imports from the other.

```
     Model/          ← shared types (GID, GameState, Agent, ActionManagement, PossibilityGraph)
    /      \
  DSL/    Engine/
   │         │
   │         ├── Resolution/  ← resolving player commands
   │         └── Simulation/ ← the living world (Rhine dataflow graph)
   │
   └── produces (GameState, PossibilityGraph)
              │
              └── consumed by Engine at startup
```

### World Creation (DSL/)

The DSL describes a world as data. `interpretDSL` is a natural transformation
from `SashaLambdaDSL` to `WorldBuilder`. The `WorldBuilder` monad accumulates a `BuilderState`, finalized into `GameState` + `PossibilityGraph`.

Content authors use smart constructors from `DSL.Vocabulary.Wiring`. The `look` smart constructor registers both the action AND the GameEvent behavior automatically — content authors never touch internals.

### World Runtime (Engine/)

Two layers, mirroring the IX prototype:

**Engine/Resolution/** — Action resolution. No Rhine, no IO. Resolves what a player command means: parses input, discovers the action, runs the veto chain, fires effects, produces narration. Functions that transform game state: `modifyAgentM`, `processActionOutcomeRegistry`, `youSeeM`, `toGameComputation`. These get lifted into the simulation graph.

**Engine/Simulation/** — The living world. The Rhine dataflow graph. Events and Behaviors: ticks fire Events, signal functions (Behaviors) respond by computing GameState changes. Compiles and actuates the Rhine network (Rhine's `flow` lives here, mirroring IX where `actuate` lives in `IX.Reactive.EventNetwork`). Calls Engine/Resolution functions inside reactive combinators.

---

## DSL Design

### Two Has\* Classes — Nothing More

One class per file. Each appears in the commit that first needs it. Everything else is plain functions.

A class earns its file when multiple action types share a polymorphic interface — a
single semantic verb that dispatches differently per action type.

HasAccess covers `open`/`close` — one semantic verb pair shared by ContainerAccessF,
PortalAccessF, and SomaticAccessF (same pattern as HasPerception with `look`).
Action types with single-instance verbs (PosturalF stand/sit, ManipulationF
lift/press/pull/cut, ControlF start, SomaticAccessF wear/remove, AcquisitionF,
DivestmentF, ConsumptionF) are plain functions in HasEffect.hs — no class needed.

```
DSL/Internal/
  HasPerception.hs     -- commit 2:  ImplicitStimulusF (later: DirectionalStimulusF, DirectionalStimulusContainerF)
  HasAccess.hs         -- commit 11: SomaticAccessF (later: ContainerAccessF commit 14, PortalAccessF commit 22)
  HasEffect.hs         -- Plain function groups, NOT classes (PosturalF, ManipulationF, ControlF, AcquisitionF, DivestmentF, ConsumptionF, TransitiveStimulusF, RogativeF, InterrogativeF, ComitativeF, DirectedImperativeF, CardinalMovementF, plus SomaticAccessF wear/remove)
  HasAction.hs         -- declareAction (unchanged)
  EffectAlgebra.hs     -- action, triggers, on (unchanged)
  EffectCluster.hs     -- SlotFill, wireSlots (unchanged)
```

### What Is Dead

The following abstractions from the old codebase are removed:

- **Capability typeclass** — Lookable, Portable, Openable, Sittable, etc. The veto system determines ability at all entity levels. The constructor IS the veto (`ImplicitStimulusF` = success, `ImplicitNoStimulusF` = denial). Slot swaps change which GID is mapped. Wrapper types that encode "this can be looked at" are redundant with the veto chain.
- **MakeBehavior typeclass** — dead
- **MakeEffect typeclass** — dead
- **HasBehavior typeclass** — dead
- **HasEffect typeclass** (as a class) — replaced by plain functions in HasEffect.hs
- **BehaviorVerb, ActionVerb type families** — dead
- **DSL/Capabilities/ module hierarchy** — dead. No Capabilities directory.
- **ObjectTransform monoid** — replaced by `andThen` composition in DSL.Vocabulary

### Smart Constructors Register GameEvent Behaviors

The `look` smart constructor in `DSL.Vocabulary.Wiring` registers both the action AND the GameEvent behavior:

```haskell
-- When wiring "look" for a scene, the smart constructor:
-- 1. Registers ImplicitStimulusF action
-- 2. Registers GameEvent behavior via RegisterGameEvent
--    The behavior finds other agents in the scene and writes
--    environmental narration: "{actor} looks around."
```

Content authors never manually register GameEvent behaviors.

---

## Reactive Architecture

Rhine replaces reactive-banana from the IX prototype. The architecture remains the same: pure game functions lifted into a reactive dataflow graph, with I/O at the edges.

### The IX Pattern

```
IX.Universe.*   — Pure game functions (no FRP, no IO)
IX.Reactive.*   — FRP dataflow graph (reactive-banana)
IX.Server.*     — IO plumbing
```

Pure functions called inside reactive combinators:

```haskell
eAgentMap = updateAMap <$> eAInput
bResourceMap = accumB initRmap $ adjustMarket <$> bMarketRolls <@ eTick
eValidated = toVAC <$> filterApply (agentExists <$> bAgentMap) eInput
```

### The SashaMud Pattern

```
Engine/Resolution/*  — Action resolution (GameState transforms, action discovery, evaluation)
Engine/Simulation/*  — World simulation (Rhine signal functions, clocks, Events, Behaviors, flow/actuate)
Server/*             — IO binding (Servant handlers, calls into Simulation)
```

### Monad Stack

```haskell
newtype GameChan a = GameChan
  { runGameChan :: EventChanT GameEvent (ReaderT AppCtx IO) a }

newtype RhineM a = RhineM
  { runRhineM :: GameStateT (ReaderT PossibilityGraph GameChan) a }
```

GameState lives in `GameStateT` inside `RhineM`. PossibilityGraph lives in a `ReaderT` between
`GameStateT` and `GameChan` — it is immutable game data, not server infrastructure. Rhine's
`flow` maintains GameState across ticks. Neither GameState nor PossibilityGraph is in AppCtx.

### hoistComputation Bridge

Pure engine computation is hoisted into the Rhine monad:

```haskell
runComputation :: GID Agent -> GameComputation Identity a -> RhineM (Either Text a)
runComputation actingAgent comp =
  let hoisted = hoistComputation liftBase comp
  in RhineM (runExceptT (runReaderT (runGameComputation hoisted) actingAgent))
```

The only per-computation input is the acting agent GID. PossibilityGraph is accessed
from the `ReaderT PossibilityGraph` layer in `RhineM` — single source of truth, not
duplicated into a context record. `GameStateT` is shared — no extraction, no reinsertion.
The engine emits a `GameEvent` after successful action processing. The `gameEventSF`
Behavior responds on `EventClock`.

### Rhine Pipeline

```haskell
rhinePipeline :: Rhine RhineM GameClock () ()
rhinePipeline =
      (playerTickSF      @@ mkHoist liftIO playerClock)
  |@| (gameEventSF       @@ mkHoist lift (EventClock :: EventClock GameEvent))
  |@| (heartbeatSF       @@ mkHoist liftIO heartbeatClock)
```

Three clocks at commit 2, growing to five:

| Clock | Type | Interval | Purpose |
|-------|------|----------|---------|
| PlayerTick | Timer | 1s | Drain command buffer, run engine, route actor narration, emit GameEvent |
| GameEventClock | EventClock | Immediate | Fires on GameEvent, Behavior responds with environmental narration |
| HeartbeatTick | Timer | 5s | Keep-alive messages to all connected clients |
| AgentTick | Timer | 30s | Advance agent-category sequences (commit 17+) |
| WorldTick | Timer | 45s | Advance world-category sequences (commit 17+) |

### Events and Behaviors

The reactive architecture follows the IX pattern: Events are discrete occurrences,
Behaviors are signal functions that respond to Events by computing GameState changes.

**Events** — things that happen:
- Tick Events: HeartbeatTick (5s), PlayerTick (1s), AgentTick (30s), WorldTick (45s)
- Player action Events: commands processed on PlayerTick
- `GameEvent`: emitted after successful action processing (carries ActionEffectKey, acting agent GID, scene GID)

**Behaviors** — signal functions that respond to Events:
- `heartbeatSF`: responds to HeartbeatTick, broadcasts keep-alive to all clients
- `playerTickSF`: responds to PlayerTick, drains command buffer, runs engine, routes narration
- `gameEventSF`: responds to GameEvent, computes environmental narration for other agents in scene
- `agentTickSF`: responds to AgentTick, advances agent-category sequences (commit 17+)
- `worldTickSF`: responds to WorldTick, advances world-category sequences (commit 17+)

**The Reactive Cycle:**

1. Commands arrive over TypedWebSocket — buffered
2. PlayerTick fires (Event) — `playerTickSF` (Behavior) drains buffer, runs engine, produces narration
3. Engine emits `GameEvent` (Event)
4. `gameEventSF` (Behavior) fires immediately — computes environmental narration, routes to other agents in scene
5. Output delivered over WebSocket as WireMessage

**GameEvent Registry** — maps ActionEffectKey to Behavior update functions (lives in
PossibilityGraph, immutable). When a `GameEvent` fires, the registry determines what
environmental narration to produce. The actor's name is resolved at runtime from GameState.

DSL smart constructors register GameEvent behaviors automatically. Content authors do
not interact with the event system directly.

---

## I/O Surface

Networking is managed by Servant on the backend and Caddy + TypeScript on the frontend.

### Servant API

```haskell
type SashaAPI =
  LoginAPI :<|> GameAPI

type LoginAPI =
  "login"
  :> ReqBody '[JSON] Credentials
  :> Post '[JSON] LoginResponse

type GameAPI =
  "game"
  :> AuthProtect SecWebSocketProtocol
  :> TypedWebSocket 'Text GameCommand WireMessage
```

Login over REST. All game I/O over one typed bidirectional WebSocket. `GameCommand` flows in, `WireMessage` flows out. The TypeScript client is generated from these servant types automatically.

### AppCtx

```haskell
data AppCtxRecord = AppCtxRecord
  { _acClients     :: !(TVar (Map ClientName Client))
  , _acPlayerMap   :: !(TVar (Map ClientName (GID Agent)))
  , _acCommandChan :: !(TChan (ClientName, ByteString))
  , _acGameLog     :: !GameLog
  , _acMetrics     :: !(Maybe Metrics)
  }
```

AppCtx holds server concerns only — connections, sessions, command channel. GameState and
PossibilityGraph live in the game layer (`GameStateT` and `ReaderT PossibilityGraph` inside
`RhineM`), not in AppCtx.

### Stack

```
Caddy          — TLS, static files, reverse proxy
Servant        — HTTP (login) + TypedWebSocket (game I/O)
Rhine          — Reactive dataflow graph (GameState in GameStateT)
Pure Engine    — State transforms, evaluation, effects
```

### Future: PostgreSQL

Authentication, authorization, and game saves via PostgreSQL (commit 5+). Auth types in API/ module. Persistence implementation in Server/Persist/.

---

## RichText: Clay.Color

### Current State

RichText uses a homemade TextColor enum with 14 terminal-era color names. SashaMud is moving to a web frontend where CSS is the styling language.

### Target State

Replace TextColor with Clay.Color. The RichText span model stays the same — only the color type changes:

```haskell
import Clay.Color (Color)

data TextStyle = TextStyle
  { tsFgColor :: Maybe Color    -- Clay.Color: RGBA, HSLA, 148 named CSS colors, color math
  , tsBold    :: Bool
  , tsItalic  :: Bool
  }

data StyledSpan = StyledSpan
  { ssStyle :: TextStyle
  , ssText  :: Text
  }

newtype RichText = RichText { unRichText :: [StyledSpan] }
```

### Why Clay.Color, Not All of Clay

Clay is a CSS stylesheet preprocessor — it generates CSS rules applied to HTML elements via selectors. Game narration is a sequence of inline styled text spans. There is no DOM to select against, no cascade. Each span is self-contained.

Clay.Color gives us the CSS color space (RGBA, HSLA, named colors, `lighten`, `darken`, `lerp`). The rest of Clay (selectors, properties, stylesheets, flexbox, grid, animation) has no application to styled text spans.

### Serialization

Clay.Color renders to CSS color strings (`#ff0000`, `rgba(255,0,0,1)`). The TypeScript frontend receives CSS color values directly. Custom ToJSON/FromJSON instances serialize Color as its CSS string representation.

---

## Dependency DAG

```
sasha-grammar ──────────────────────────
   │                        │
   │                   sasha-vocabulary
   │                        │
   └──────── sasha ─────────┘
                │
           sashamud-world
                │
          sashamud-server
```

---

## Migration From Current Structure

### Packages That Merge Into sasha

| Current Package | Destination | Notes |
|----------------|-------------|-------|
| sasha-core | sasha (Model/) | World-model types move to the application package. |
| sasha-dsl | sasha (DSL/) | DSL is the engine's build phase. |
| sasha-engine | sasha (Engine/) | Resolution + Simulation. |
| sasha-api | sasha (API/) | I/O contract defined alongside implementation. |
| sasha-server | sasha (Server/) | Absorbed. |
| sasha-web/server | sasha (Server/) | Absorbed. |
| sashamud | sashamud-world | One-module wrapper absorbed into content package. |

### Grammar Types That Move to sasha-grammar

| Current Location (sasha-core) | New Location |
|-------------------------------|--------------|
| Model.Parser.Lexer (Lexeme enum) | sasha-grammar |
| Model.Parser (Sentence, Imperative) | sasha-grammar |
| Model.Parser.Atomics.* (verb/noun/preposition types) | sasha-grammar |
| Model.Parser.Composites.* (phrase types) | sasha-grammar |
| Model.Parser.GCase (NounKey, VerbKey) | sasha-grammar |
| Model.Parser.VocabConfig | sasha-grammar |

### Dead Code Removed

| Abstraction | Status |
|------------|--------|
| Capability typeclass (Lookable, Portable, etc.) | Dead — veto chain replaces it |
| MakeBehavior, MakeEffect typeclasses | Dead |
| HasBehavior typeclass | Dead |
| BehaviorVerb, ActionVerb type families | Dead |
| DSL/Capabilities/ module hierarchy | Dead |
| ObjectTransform monoid wrapper | Dead — replaced by andThen |
| 22 individual HasX classes (HasLook, HasStand, etc.) | Dead — replaced by 2 Has* classes + plain functions |

### cabal.project

```cabal
packages:
  ./sasha-grammar
  ./sasha-vocabulary
  ./sasha
  ./sashamud-world
  ./sashamud-server

test-show-details: streaming
```
