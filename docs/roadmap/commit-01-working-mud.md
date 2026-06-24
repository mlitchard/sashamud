# Commit 1: Player Login and Heartbeat

Conforms to: [monorepo-redesign.md](../monorepo-redesign.md) (living document, subject to correction)

Old code reference: `/home/mlitchard/gitlab/sasha/` (patterns, not gospel)

## What Ships

The complete pipeline, minimalized. A player opens a browser, logs in, connects over WebSocket, and receives heartbeat messages produced by the Rhine engine. Every layer of the pipeline works end to end: Nix builds all four Haskell packages, generates TypeScript types from Haskell wire protocol types, builds the TypeScript client, deploys behind Caddy. `nix flake check` is green — Haskell tests pass, TypeScript compiles against generated types.

Heartbeats are the game content — the engine writes a `SystemMessage` to GameState, routed to every connected client. Commit 2 adds the first player-interactive content ("look").

## What's NOT In

Parser, action resolution, GameEvent behaviors. Those come in commit 2. No Engine/Resolution/ directory. No ConstraintRefinement/ directory.

All pipeline stages exist in simplest form: DSL describes the lobby, interpretDSL produces GameState + PossibilityGraph, Rhine engine runs heartbeats, server routes messages, TypeScript client renders.

---

## Packages

All four packages build. sasha-grammar and sasha-vocabulary are stubs. sashamud-world provides a minimal world (lobby scene + player agent template).

| Package | Commit 1 Content |
|---------|-----------------|
| sasha-grammar | Stub — builds, exports nothing |
| sasha-vocabulary | Stub — builds, exports nothing |
| sasha | Server, API, Rhine engine, Model types (full skeleton) |
| sashamud-world | Minimal world: lobby scene, default player agent, `sashaMudWorld` constructor |

```cabal
-- cabal.project
packages:
  ./sasha-grammar
  ./sasha-vocabulary
  ./sasha
  ./sashamud-world

test-show-details: streaming
```

---

## Module Layout: sasha (Commit 1 Subset)

```
sasha/src/
│
├── SashaPrelude.hs                  -- Custom prelude (NoImplicitPrelude enforced)
│
├── Model/                           -- SHARED TYPES (full skeleton, empty maps)
│   ├── Core.hs                      -- GameState, PossibilityGraph, Agent, Scene, World, Defaults, EntityKey
│   ├── Core/
│   │   └── Mappings.hs             -- ActionManagement types, ActionManagementFunctions
│   ├── GID.hs                       -- GID newtype (phantom-typed), role phantom
│   ├── RichText.hs                  -- RichText, StyledSpan, TextStyle (TextColor enum)
│   ├── WireProtocol.hs              -- WireMessage (all constructors)
│   └── RandomPool.hs               -- RNG stream types
│
├── Error.hs                         -- error combinators
│
├── DSL/                             -- WORLD CREATION (minimal)
│   ├── Builder.hs                   -- interpretDSL, WorldBuilder, runWorldBuilder
│   ├── Vocabulary.hs                -- buildScene, named, described
│   └── Model/EDSL/
│       └── SashaLambdaDSL.hs        -- GADT: DeclareSceneGID, RegisterScene, FinalizeGameState
│
├── Engine/                          -- WORLD RUNTIME (basic engine)
│   └── Simulation/                  -- Rhine FRP network
│       ├── EffectNetwork.hs         -- rhinePipeline, RhineM, signal functions, routing
│       └── Clocks.hs               -- HeartbeatTick, GameClock
│
├── API/                             -- I/O contracts
│   ├── Types.hs                     -- GameCommand, PlayerName, LoginResponse
│   ├── Routes.hs                    -- Servant API type
│   └── TSClient.hs                  -- TypeScript client codegen
│
└── Server/                          -- I/O binding
    ├── App.hs                       -- AppCtx (server concerns only)
    ├── Server.hs                    -- startServer
    ├── Authentication.hs            -- auth pipeline (acConnections MVar replaces session registry)
    ├── GameWebSocket.hs             -- WebSocket handler
    ├── Validator.hs                 -- input validation
    └── Log.hs                       -- structured logging categories
```

### Consolidation Decisions

**Model/Core/ consolidated into Core.hs** — GameState, Agent, Scene, World, EntityKey, and Defaults all live in one file rather than separate files per type. The types are small at commit 1 and tightly interdependent. Mappings.hs stays separate because ActionManagement types are a distinct concern.

**Engine/Simulation/ consolidated into EffectNetwork.hs** — RhineM monad, signal functions, and routing all live in one file rather than GameLoop.hs + Monad.hs + Route.hs. At commit 1 the Rhine network is minimal (heartbeat + player tick). Clocks.hs stays separate.

**Session.hs removed** — The old GameSessionRegistry (TVar of Map Text GameSession) is replaced by acConnections MVar in AppCtx. Session lifecycle (create on login, bind on WS connect, cleanup on disconnect) is handled directly in Authentication.hs and GameWebSocket.hs.

**What does NOT exist in commit 1:**
- `DSL/Internal/` — commit 2 (HasPerception, HasAction, HasEffect, EffectAlgebra, EffectCluster, TypeMappings)
- `DSL/Vocabulary/Wiring.hs` — commit 2 (action + GameEvent behavior registration)
- `DSL/Effects.hs` — commit 2 (narrate, narrateLook)
- `ConstraintRefinement/` — commit 2
- `Engine/Resolution/` — commit 2
- `Engine/Simulation/Bridge.hs` — commit 2 (nothing to hoist)
- `Engine/Simulation/Sequences.hs` — commit 17
- `Model/Core/Object.hs` — commit 6
- `Model/Core/GameEvent.hs` — commit 2
- `Server/Persist/` — commit 5
- `Server/Metrics.hs` — deferred

---

## Model Types — Full Skeleton

All types exist from commit 1. Maps are empty. The skeleton is complete so commit 2 can populate it without restructuring.

### GID

```haskell
type role GID phantom
type GID :: Type -> Type
newtype GID a = GID { unGID :: Int }
  deriving newtype (Eq, Ord, Show)
```

### GameState

```haskell
data GameState = GameState
  { _world              :: !World
  , _narration          :: !Narration
  , _evaluation         :: !Evaluator
  , _gameStatus         :: !GameStatus
  }
```

Commit 1 fields are minimal — `_world` with empty maps, `_narration` empty, `_evaluation` default, `_gameStatus = Running`. Later commits add `_activeFrameEffects`, `_newActiveSequences`, `_firedEffects`, `_actionEffectOverrides`, `_triggerStates` as needed.

### PossibilityGraph

```haskell
data PossibilityGraph = PossibilityGraph
  { _actionMaps          :: !ActionMaps
  , _entityActionEffects :: !EntityActionRegistry
  , _worldOutcomeEffects :: !WorldOutcomeRegistry
  }
```

Empty at commit 1. Populated by the DSL in commit 2. Later commits add `_sequenceFrames'`, `_sequenceTriggers`, `_frameEffectLinks`, `_frameEffectRegistry`, `_dynamicEffects`, `_gameEventRegistry` as needed.

### World

```haskell
data World = World
  { _objectMap              :: GIDToDataMap Object Object
  , _sceneMap               :: GIDToDataMap Scene Scene
  , _spatialRelationshipMap :: SpatialRelationshipMap
  , _globalSemanticMap      :: Map NounKey (Set (GID Object))
  , _perceptionMap          :: Map DirectionalStimulusNounPhrase (Set (GID Object))
  , _agentMap               :: AgentMap
  }
```

Lobby scene in `_sceneMap`, agents added dynamically on login to `_agentMap`. Other maps empty at commit 1.

### Agent

```haskell
data Agent = Agent
  { _agentShortName        :: Text
  , _agentDescription      :: RichText
  , _agentTitle            :: Text
  , _agentActionManagement :: ActionManagementFunctions
  , _agentCurrentScene     :: GID Scene
  , _agentKind             :: AgentKind
  }
```

Commit 1 fields are minimal. Later commits add `_agentInventory`, `_agentEffectMap`, `_agentDescriptives`, `_agentFollowers` as needed.

### Scene

```haskell
data Scene = Scene
  { _title                 :: Text
  , _sceneDescription      :: RichText
  , _sceneActionManagement :: ActionManagementFunctions
  , _sceneAgents           :: Set (GID Agent)
  }
```

Commit 1 fields are minimal. Later commits add `_sceneIntroduction`, `_objectSemanticMap`, `_sceneObjects`, `_agentSemanticMap`, `_sceneAgentOverlays` as needed.

### Narration

```haskell
data Narration = Narration
  { _playerAction      :: ![RichText]
  , _actionConsequence  :: ![RichText]
  , _actionEpilogue     :: ![RichText]
  }
  deriving (Monoid, Semigroup) via (Generically Narration)
```

Commit 1 fields are minimal. Later commits add `_proximityAdjacent`, `_proximityDistant`, `_departureNarration`, `_arrivalNarration` as needed.

### RichText — Clay.Color from Day One

```haskell
import Clay.Color (Color)

data TextStyle = TextStyle
  { tsFgColor :: Maybe Color
  , tsBold    :: Bool
  , tsItalic  :: Bool
  }

data StyledSpan = StyledSpan
  { ssStyle :: TextStyle
  , ssText  :: Text
  }

newtype RichText = RichText { unRichText :: [StyledSpan] }
```

Clay.Color from commit 1. No terminal-era TextColor enum. The TypeScript client receives CSS color strings directly. Custom ToJSON/FromJSON instances serialize Color as its CSS string representation (`"#ff0000"`, `"rgba(255,0,0,1)"`).

### WireMessage

```haskell
data WireMessage
  = SessionId Text
  | GameNarration [RichText]
  | CommandResponse [RichText]
  | ChatMessage Text
  | SystemMessage Text
  | AnalysisData (Map Text [RichText])
```

All constructors exist from commit 1 (TypeScript client must compile against them). Only `SystemMessage` carries content in commit 1 (heartbeats). Only `SessionId` is sent on connect.

---

## Monad Stack

Established in commit 1. PossibilityGraph lives in the game layer, not the server layer.

```haskell
newtype GameChan a = GameChan
  { runGameChan :: EventChanT GameEvent (ReaderT AppCtx IO) a }

newtype RhineM a = RhineM
  { runRhineM :: GameStateT (ReaderT PossibilityGraph GameChan) a }
```

- `GameStateT` — mutable game state (full skeleton, empty maps at commit 1)
- `ReaderT PossibilityGraph` — immutable game data (empty at commit 1 — DSL produces it, no actions registered yet)
- `GameChan` — Rhine event channel + server context
- `AppCtx` — server concerns only (connections, sessions, command channel)

### Single Source of Truth

PossibilityGraph lives in ONE place: the `ReaderT PossibilityGraph` layer in `RhineM`. Engine computations access it from the monad stack after hoisting — it is not duplicated into a per-computation context record. The only per-computation input to `runComputation` is the acting agent GID.

---

## AppCtx — Server Concerns Only

```haskell
data AppCtxRecord = AppCtxRecord
  { _acClients     :: !(TVar (Map ClientName Client))
  , _acPlayerMap   :: !(TVar (Map ClientName (GID Agent)))
  , _acCommandChan :: !(TChan (ClientName, ByteString))
  , _acGameLog     :: !GameLog
  }
```

No GameState. No PossibilityGraph. Those live in `RhineM`. `_acPlayerMap` maps sessionId -> `GID Agent` — populated on login as agents are created. `_acMetrics` added later.

---

## Rhine Pipeline — Heartbeat Only

```haskell
type HeartbeatTick = Millisecond 5000
type PlayerTick    = Millisecond 1000

rhinePipeline :: Rhine RhineM GameClock () ()
rhinePipeline =
      (playerTickSF  @@ (waitClock :: PlayerTick))
  |@| (heartbeatSF   @@ (waitClock :: HeartbeatTick))
```

Two clocks from commit 1. Two Behaviors:

- `heartbeatSF`: responds to HeartbeatTick (5s), broadcasts `SystemMessage "*** heartbeat"` to all connected clients
- `playerTickSF`: responds to PlayerTick (1s), drains `_acCommandChan` (STM). No commands arrive yet — the drain is a no-op. The infrastructure exists so commit 2 wires command processing without restructuring.

The STM command channel gathers all player input from all sessions every PlayerTick. WebSocket handlers write commands to `_acCommandChan`, `playerTickSF` drains it. In commit 1 the channel is empty — the pipeline exists, the content doesn't.

Commit 2 adds `GameEventClock` (EventClock) for GameEvent Behaviors. Commit 17 adds `AgentTick` (30s) and `WorldTick` (45s).

---

## DSL — Simplest Form

The DSL exists in commit 1. It describes the lobby scene. `interpretDSL` produces `GameState` + `PossibilityGraph`. The pipeline stage is real, just minimal.

### SashaLambdaDSL (Commit 1 GADT Constructors)

```haskell
data SashaLambdaDSL a where
  DeclareSceneGID  :: Text -> SashaLambdaDSL (GID Scene)
  RegisterScene    :: GID Scene -> (Scene -> SashaLambdaDSL Scene) -> SashaLambdaDSL ()
  FinalizeGameState :: SashaLambdaDSL ()
```

Three constructors. Enough to declare a scene, register it with a title and description, and finalize the game state. Commit 2 adds `DeclareImplicitStimulusGID`, `RegisterGameEvent`, agent registration, and the rest.

### Builder.hs

```haskell
interpretDSL :: SashaLambdaDSL a -> WorldBuilder a
runWorldBuilder :: WorldBuilder () -> (GameState, PossibilityGraph)
```

`interpretDSL` is the natural transformation from DSL to builder monad. `runWorldBuilder` finalizes into `GameState` (with lobby scene) + `PossibilityGraph` (empty — no actions registered).

### Vocabulary.hs

```haskell
buildScene :: Text -> Text -> (Scene -> SashaLambdaDSL Scene) -> SashaLambdaDSL (GID Scene)
named :: Text -> Scene -> SashaLambdaDSL Scene
described :: Text -> Scene -> SashaLambdaDSL Scene
```

Minimal smart constructors for scene description. Commit 2 adds `buildAgent`, `andThen`, `attach`, and action wiring via `DSL.Vocabulary.Wiring`.

---

## sashamud-world — Lobby

```
sashamud-world/src/
  SashaMudWorld.hs         -- sashaMudWorld :: SashaLambdaDSL (), defaultPlayerAgent
```

```haskell
sashaMudWorld :: SashaLambdaDSL ()
sashaMudWorld = do
  _lobbyGID <- buildScene "lobby" "The Lobby"
    (named "The Lobby" `andThen` described "A spacious lobby with high ceilings.")
  pure ()
```

One scene. No objects, no actions, no GameEvent behaviors. Player agents are created dynamically at login time using `defaultPlayerAgent` and placed in the lobby.

```haskell
defaultPlayerAgent :: Text -> GID Scene -> Agent
defaultPlayerAgent playerName lobbyGID = Agent
  { _agentShortName        = playerName
  , _agentDescription      = plain "A player."
  , _agentTitle            = ""
  , _agentActionManagement = defaultActionManagement
  , _agentCurrentScene     = lobbyGID
  , _agentKind             = PlayerAgent
  }
```

Commit 2 adds look actions to the lobby, wires GameEvent behaviors, and triggers "look" on login.

---

## Servant API

```haskell
type LoginAPI =
  "api" :> "game" :> "login"
  :> ReqBody '[JSON] PlayerName
  :> Post '[JSON] LoginResponse

type GameCommandAPI =
  "api" :> "game" :> Capture "sessionId" Text
  :> "command"
  :> ReqBody '[JSON] GameCommand
  :> PostNoContent

type SashaAPI =
       LoginAPI
  :<|> GameCommandAPI
  :<|> "ws" :> "game" :> Capture "sessionId" Text
       :> TypedWebSocket 'Text Text WireMessage
```

All three endpoints exist from commit 1. `GameCommandAPI` accepts commands — they are buffered in `_acCommandChan`. `playerTickSF` drains the channel every 1s but action resolution is not wired until commit 2.

---

## Login Flow (Commit 1 — Multi-Player from Day One)

1. Client shows login overlay — user enters character name
2. Client sends HTTP POST to `/api/game/login` with `PlayerName`
3. Server validates name (non-empty, length limit)
4. Server creates Agent from default template, sets `_agentShortName` to the name
5. Server assigns agent to lobby scene (adds to `_sceneAgents`, sets `_agentCurrentScene`)
6. Server stores agent in World `_agentMap`
7. Server generates a sessionId, maps sessionId -> `GID Agent` in `_acPlayerMap`
8. Server returns `LoginResponse` (sessionId)
9. Client connects WebSocket to `/ws/game/:sessionId`
10. Server validates sessionId, creates `Client` entry in `_acClients`
11. Server sends `SessionId` message over WebSocket (confirmation)
12. Heartbeats begin flowing — `SystemMessage "*** heartbeat"` every 5s
13. On disconnect: agent removed from lobby scene and `_agentMap`, client removed from `_acClients`, session removed

Every player is a real agent in a real world from commit 1. Multiple players connect, each gets their own agent in the lobby. The multi-player foundation is never absent.

---

## TypeScript Client — Full Pipeline

The complete TypeScript client ships in commit 1. The pipeline is complete. Game content is heartbeats (engine writes `SystemMessage` to GameState, routed to clients). Commit 2 adds player-interactive content.

### Build Chain

```
TSClient.hs generates client.ts (Haskell wire types -> TypeScript types)
  -> packages/type-gen-output/src/client.ts
  -> apps/sasha-web imports from @sasha/type-gen-output/client
  -> Vite builds static bundle
```

### Source Files

| File | Purpose |
|------|---------|
| `src/main.ts` | Entry point, login overlay, login flow |
| `src/game/GameConnection.ts` | WebSocket manager, reconnect logic |
| `src/game/ViewportManager.ts` | Multi-viewport UI (scene, system, meta, parser, state, graphics, map) |
| `src/game/RichTextRenderer.ts` | Renders StyledSpan with CSS color strings (Clay.Color) |
| `src/game/createDOM.ts` | DOM creation, toolbar, command input, status bar, Selenium test hooks |
| `src/index.html` | Minimal HTML shell |
| `src/styles/main.css` | Styling |

### What Flows in Commit 1

- Login overlay -> POST /login -> sessionId -> WebSocket connect
- `SessionId` message on connect (confirmation)
- `SystemMessage "*** heartbeat"` every 5s -> displayed in system viewport
- Command input exists but action resolution is not wired until commit 2

### RichTextRenderer — Clay.Color

The old `TEXT_COLORS` lookup table is replaced. With Clay.Color, the server sends CSS color strings directly. The renderer applies them to `el.style.color` without translation.

### Type Generation Bridge

`TSClient.hs` generates TypeScript types from Haskell types using `servant-client-typescript`:

```haskell
client :: Text
client = tsClient
  @'[ TSDef TextStyle
    , TSDef StyledSpan
    , TSDef RichText
    , TSDef WireMessage
    , TSDef GameCommand
    , TSDef PlayerName
    , TSDef LoginResponse
    ] @SashaAPI
```

Note: `TextColor` is gone — `tsFgColor` becomes `string | null` in TypeScript (CSS color string).

---

## Caddy

```
:8080 {
  handle /ws/* {
    reverse_proxy localhost:8081
  }

  handle /api/* {
    reverse_proxy localhost:8081
  }

  handle {
    root * web/apps/sasha-web/dist
    try_files {path} /index.html
    file_server
  }
}
```

Development Caddyfile. Production uses NixOS caddy module.

---

## Nix Flake

`nix flake check` builds and tests everything:

1. Four Haskell packages compile (sasha-grammar, sasha-vocabulary, sasha, sashamud-world)
2. Haskell tests pass
3. Type generator executable runs — produces `client.ts`
4. TypeScript client compiles against generated types (Vite build)
5. If a Haskell wire type changes and TypeScript doesn't match, the build fails

The flake provides:
- `devShells.default` — Haskell dev shell with hlint, stylish-haskell, caddy, npm
- `packages` — Haskell packages + TypeScript client build
- `checks` — Haskell tests + TypeScript compilation
- `apps` — `mud-web` (Caddy + server + Vite dev), `start-sashamud` (production build)

The build sequence for `start-sashamud`:
```bash
cabal run exe:sasha-client-generator -- web/packages/type-gen-output/src/client.ts
(cd web && npm install && npm run build)
caddy run --config Caddyfile &
cabal run exe:sasha-server &
```

---

## SashaPrelude

`NoImplicitPrelude` is enforced in every package. `SashaPrelude` is the project's custom prelude, defined in `sasha` and imported by all packages. Contains safe re-exports from `GHC.Base`, `Data.Foldable`, `Data.Text`, etc.

---

## Tests

Every test executes during `nix flake check`. Test stanzas use `executable`, not `test-suite`. Tests use hspec-discover.

### Property Tests (roundtrips)

- JSON roundtrip: `WireMessage` (all constructors survive encode/decode)
- JSON roundtrip: `RichText`, `StyledSpan`, `TextStyle` (Clay.Color serialization)
- JSON roundtrip: `LoginResponse`, `PlayerName`, `GameCommand`

### Unit Tests

- `SashaPrelude` provides expected re-exports
- `GameState` default construction — lobby in sceneMap, `_gameStatus = Running`
- `PossibilityGraph` empty construction (no actions registered)
- `Narration` mempty is identity under `(<>)`
- RichText smart constructors (`plain`, `colored`, `bold`, `boldColored`) produce correct spans
- RichText `toPlainText` strips styling
- `defaultPlayerAgent` creates agent with correct name and scene assignment
- DSL `runWorldBuilder` produces GameState with lobby scene

### Integration Tests

- Login flow: POST `/api/game/login` with valid name returns sessionId
- Login flow: POST `/api/game/login` with empty name returns error
- Login flow: returned sessionId connects successfully to WebSocket
- Login flow: invalid sessionId on WebSocket connect is rejected
- Login creates agent in `_agentMap` with correct `_agentShortName`
- Login assigns agent to lobby scene (`_sceneAgents` contains agent GID)
- Heartbeat delivery: connected client receives `SystemMessage` within 5s
- Multi-player: two players login, both agents exist in lobby `_sceneAgents`
- Multi-player: both clients receive heartbeats independently
- Disconnect: agent removed from lobby scene and `_agentMap`, client removed from `_acClients`
- TypeScript compilation: `nix flake check` verifies TypeScript client compiles against generated types

### What Tests Do NOT Cover (Commit 2+)

- Engine computation, action resolution, narration production
- Parser/lexer roundtrips
- GameEvent behaviors (environmental narration)
- `runComputation` / `hoistComputation` bridge
- Per-agent narration isolation
- Action wiring via DSL smart constructors
