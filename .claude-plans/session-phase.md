# SessionPhase Unification — Session Lifecycle as a Sum Type

**STATUS: EXECUTED** (2026-07-12, branch 4-login-bug-fix, four gated steps, each green through nix flake check)

## Why

Login race (diagnosed 2026-07-12): `loginHandler` queues `PlayerJoined` on `acJoinChan` at
HTTP login (Server.hs:75). The client's websocket registers its send function in
`acConnections` only after it receives the HTTP response and dials the socket. The
PlayerTick chain drains the join, runs the auto-look, and `deliverOutbound` looks up a
send function that is not there yet — `SendDropped`. The joiner loses the scene
description and presence listing; already-connected witnesses see "x has arrived." /
"x looks around." because their sockets are live.

The deeper disease: one session's lifecycle is smeared across `acConnections` (socket
truth) and `acPlayerMap` (join truth), plus the would-be pending state, with mutual
exclusion enforced by nothing. This plan makes the lifecycle one map with phases as a
sum type — being in two phases becomes unrepresentable.

## Target shape

```haskell
data SessionPhase
  = AwaitingSocket PlayerNameVAL
  | AwaitingJoin PlayerNameVAL ([MessageFrom] -> IO ())
  | InGame ([MessageFrom] -> IO ()) (GID Agent)

acSessions :: MVar (Map SessionId SessionPhase)
```

Transitions (every one atomic under `modifyMVar_`):

| Event | Transition |
|---|---|
| HTTP login | insert `AwaitingSocket name`; evict stale `AwaitingSocket` entries with the same name (self-heal for failed connects). Emits nothing to `acJoinChan`. |
| websocket attach, `AwaitingSocket name` found | promote to `AwaitingJoin name sendMsgs`; write `PlayerJoined sid name` to `acJoinChan` |
| websocket attach, `AwaitingJoin name _` found | replace send function (`AwaitingJoin name sendMsgs`); no second `PlayerJoined` |
| websocket attach, `InGame _ gid` found | replace send function (`InGame sendMsgs gid`) |
| websocket attach, no entry | no session created — deaf socket. Inbound from it drops in `processInputSF` (gid lookup misses); sends to it log `SendDropped`. Preserves today's stale-token behavior |
| `executeJoin` (chain, after GID resolution) | `AwaitingJoin name send` → `InGame send gid`; any other phase or missing entry → leave untouched (player vanished mid-join; subsequent sends drop) |
| websocket disconnect (`handle`) | delete entry |
| `logoutHandler` | delete entry |
| `deliverOutbound` ConnectionException | delete entry |

Projections, total by construction, exported from Server.App (precedent: `PInt` with
`succPInt`/`unPInt` in the same module):

```haskell
sessionGid :: SessionPhase -> Maybe (GID Agent)
sessionGid (AwaitingSocket _) = Nothing
sessionGid (AwaitingJoin _ _) = Nothing
sessionGid (InGame _ gid)     = Just gid

sessionSend :: SessionPhase -> Maybe ([MessageFrom] -> IO ())
sessionSend (AwaitingSocket _)   = Nothing
sessionSend (AwaitingJoin _ f)   = Just f
sessionSend (InGame f _)         = Just f
```

Invariants preserved:
- One authority per question — is-a-player = `acKnownPlayers` (unchanged); is-connected =
  `acSessions` phase; is-in-scene = `sceneAgents`; character-or-object = `AgentKind`.
- Departure detection stays session-based: gid ∈ `acKnownPlayers` ∧ gid ∉ {InGame gids}.
- Game state vs server state split unchanged: `acSessions` is server truth in AppCtx,
  written by server threads and `executeJoin`; GameState stays in AccumT with the chain
  as single writer.
- `acKnownPlayers` + `acNextAgentId` persistence debt unchanged.
- `SessionPhase` carries a function — no Eq/Show/JSON, never a wire type, never in
  JSONSpec.

Race fixed by construction: `PlayerJoined` cannot exist before a send function does.

## Gate

Every step ends with `nix flake check -L` green (the `check` shelper). That gate
includes: -Werror on all five packages, hlint, stylish-haskell formatting, cabal-fmt,
ts checks, grammar tests, sasha-tests, run-integration-tests (sashamud-server test
suite = Integration.LoginLogoutSpec), and run-end-to-end (LoginSpec/RoseSpec via
Selenium). Run `fmt-haskell` before each check. One commit per step.

**Execution rule (critique #11 pattern): verify every file's actual content and imports
at execution time before editing.** The tree flipped once during diagnosis (EffectNetwork
↔ SignalNetwork); line numbers below are from the SignalNetwork-shaped tree and are
orientation, not gospel. In particular Integration/LoginLogoutSpec.hs and
SeleniumHarness.hs were last read importing `Engine.Simulation.EffectNetwork` — confirm
they now import `Engine.Simulation.SignalNetwork` before touching them.

---

## Step 1 — SessionPhase lands in Server/App.hs

**Files: sasha/src/Server/App.hs**

- Add `SessionPhase` (three constructors above), `sessionGid`, `sessionSend`.
- Add field `acSessions :: MVar (Map SessionId SessionPhase)` to `AppCtx`.
- `newAppCtx`: `sessions <- newMVar mempty`, wire into the record.
- Export `SessionPhase (AwaitingSocket, AwaitingJoin, InGame)`, `sessionGid`,
  `sessionSend` (explicit constructor list — no `(..)` on the new type; note the
  existing exports use `(..)`, follow the explicit-list rule for the new names).
- All needed imports (`MVar`, `Map`, `MessageFrom`, `PlayerNameVAL`, `GID`, `Agent`,
  `SessionId`) are already in App.hs — no import changes expected.

No reader, no writer yet. Old fields untouched. Exported names produce no -Werror
noise.

**Green because:** nothing else changes; all tests exercise the old fields.

---

## Step 2 — Socket truth moves: acConnections dies, PlayerJoined fires at socket attach

This step fixes the login race.

**Files: sasha/src/Server/Server.hs, sasha/src/Server/GameWebSocket.hs,
sashamud-server/test/Integration/LoginLogoutSpec.hs**

### Server.hs — loginHandler
Replace the `acJoinChan` write (currently :74-75) with:

```haskell
liftIO $ modifyMVar_ (acSessions ctx)
  (pure . insert sessionId (AwaitingSocket playerName) . Data.Map.Strict.filter keepEntry)
  where
    keepEntry (AwaitingSocket n) = n /= playerName
    keepEntry (AwaitingJoin _ _) = True
    keepEntry (InGame _ _)       = True
```

(Exact placement of `keepEntry` — `where` on the handler or `let` — decided at the
file. `filter` from Data.Map.Strict collides with the SashaPrelude list `filter`:
qualified use with the module-name qualifier per house rule. If that reads wrong at
execution time, STOP and ask.)

`PlayerLogin` log line and `LoginResponse` stay as they are.

### Server.hs — logoutHandler
Delete the session entry from `acSessions`; keep the `acPlayerMap` delete for this step
(join truth is still `acPlayerMap` until Step 3). The `acConnections` delete goes away
with the field.

### Server.hs — deliverOutbound
Read `acSessions`; route via `sessionSend`:

```haskell
sessions <- readMVar (acSessions ctx)
case lookup sid sessions >>= sessionSend of
  Nothing       -> writeLog (acGameLog ctx) (SendDropped sid)
  Just sendMsgs -> catches (sendMsgs [wireMsg]) [...]
```

ConnectionException handler: delete the `acSessions` entry; keep the `acPlayerMap`
delete for this step.

### GameWebSocket.hs — attach
Replace the unconditional `acConnections` insert with the phase transition:

```haskell
modifyMVar_ (acSessions ctx) $ \sessions ->
  case Map.lookup sessionId sessions of
    Just (AwaitingSocket name) -> do
      atomically $ writeTChan (acJoinChan ctx) (PlayerJoined sessionId name)
      pure (Map.insert sessionId (AwaitingJoin name sendMsgs) sessions)
    Just (AwaitingJoin name _) ->
      pure (Map.insert sessionId (AwaitingJoin name sendMsgs) sessions)
    Just (InGame _ gid) ->
      pure (Map.insert sessionId (InGame sendMsgs gid) sessions)
    Nothing ->
      pure sessions
```

(GameWebSocket.hs already uses the qualified-Map style — keep the file's existing
import style. New imports: `PlayerJoined`, `acJoinChan`, `acSessions`, TChan write —
verify against the actual file.)

`handle` (disconnect): delete the `acSessions` entry; keep the `acPlayerMap` delete for
this step.

### App.hs — remove acConnections
Delete the field, its `newMVar` line, and its export usage sites are now gone.
`SignalNetwork.hs` never imported `acConnections` — only Server.hs and GameWebSocket.hs
did (plus the integration spec).

### executeJoin, SFs — untouched this step
`executeJoin` still writes `acPlayerMap`; sessions stay `AwaitingJoin` (send function
present, so delivery works). All SFs still read `acPlayerMap`, which `executeJoin`
still maintains. The system is consistent: `acSessions` = socket truth, `acPlayerMap` =
join truth, one question each.

### Integration/LoginLogoutSpec.hs — three tests change
These tests codified the race (they pass today only because an in-process localhost
websocket usually wins a 1-second tick race; a browser behind caddy loses it):

1. **"login creates agent in agentMap with correct agentShortName"** — currently HTTP
   login, no websocket, waits 2s, asserts `sid ∈ acPlayerMap` ∧ name ∈ `acKnownPlayers`.
   Under SessionPhase no socket ⇒ no join, by design. Rewrite: login, `connectWS`,
   `receiveUntil … isLookNarration` (auto-look proves the join executed), then assert
   name ∈ `acKnownPlayers`. No `acPlayerMap` assertion — this test must not need
   another rewrite in Step 3.
2. **"multi-player: two players login, both in lobby"** — same disease. Rewrite: both
   login, both `connectWS`, both receive auto-look narration; assert both names ∈
   `acKnownPlayers`.
3. **"logout: … maps cleaned"** — reads `acConnections` (field dies this step) and
   `acPlayerMap` (dies Step 3). Rewrite the map assertions to:
   `member sid2 sessions shouldBe False` (acSessions) + name ∈ `acKnownPlayers`
   unchanged. One rewrite covers both steps.

Import list of the spec changes accordingly (`acSessions` in, `acConnections` out;
`acPlayerMap` import should disappear from the spec entirely in this step so Step 3
does not touch the file).

**Green because:** join truth still flows through `acPlayerMap` exactly as before;
socket truth has one writer path with strictly earlier registration than any send;
e2e LoginSpec (login → ws → heartbeat) works — heartbeat reads `acPlayerMap`, still
maintained; the three rewritten integration tests assert the new, stronger behavior.
The existing "login auto-look delivers the lobby description" test — the bug's
regression guard — now passes by construction instead of by winning a race.

---

## Step 3 — Join truth moves: acPlayerMap dies, SFs read acSessions

**Files: sasha/src/Engine/Simulation/SignalNetwork.hs, sasha/src/Server/Server.hs,
sasha/src/Server/GameWebSocket.hs, sasha/src/Server/App.hs**

### SignalNetwork.hs — executeJoin
Replace both `modifyMVar_ (acPlayerMap ctx) (pure . insert sid gid)` calls with the
promotion:

```haskell
modifyMVar_ (acSessions ctx) $ \sessions ->
  pure $ case lookup sid sessions of
    Just (AwaitingJoin _ send) -> insert sid (InGame send gid) sessions
    Just (AwaitingSocket _)    -> sessions
    Just (InGame _ _)          -> sessions
    Nothing                    -> sessions
```

`acKnownPlayers` insert (NewPlayerJoined branch), Welcome/Welcome-back messages, and
the auto-look `GameCommand "look"` write stay exactly as they are.

### SignalNetwork.hs — the four readers
Each SF that reads `acPlayerMap` reads `acSessions` instead and projects InGame pairs
(current MVar-read pattern preserved: each SF reads what it needs, deliverNarrationSF
at tick end):

- `heartbeatSF`: sids of InGame phases —
  `[sid | (sid, phase) <- assocs sessions, Just _ <- [sessionGid phase]]`
- `processLeavesSF`: `activeGids` = gids projected from InGame phases
  (`mapMaybe sessionGid (elems sessions)` shape); `acKnownPlayers` read unchanged
- `processInputSF`: sid→gid via `lookup sid sessions >>= sessionGid`. This read stays
  positioned after `executeJoinsSF` in the chain — the mid-tick InGame promotion is
  what routes the new player's auto-look in the same tick
- `deliverNarrationSF`: `targetSids` = sids whose `sessionGid` equals the narration's
  agent gid

Exact list-comprehension vs `mapMaybe` shapes decided at the file against what
SashaPrelude exports; no partial matches anywhere.

### Remove acPlayerMap
- App.hs: delete field + `newMVar` line.
- Server.hs: drop the `acPlayerMap` deletes kept in Step 2 (logoutHandler,
  deliverOutbound exception handler).
- GameWebSocket.hs: drop the `acPlayerMap` delete in `handle`.
- Import lists updated everywhere (`acPlayerMap` gone, `acSessions`/`sessionGid` in).

### Tests
Step 2 already removed every `acPlayerMap` reference from the integration spec —
verify with a grep before building; if any test still references it, that is a Step 2
escape and gets fixed as such. SeleniumHarness/e2e specs drive the server over the
wire and touch no AppCtx internals (verify at execution).

**Green because:** the full pipeline speaks `acSessions`; heartbeat/narration/leaves/
input behavior is the same projection the old map encoded; integration and e2e tests
assert wire-visible behavior that has not changed since Step 2.

---

## Step 4 — Race reproducer test + record straightening

**Files: sashamud-server/test/Integration/LoginLogoutSpec.hs,
.claude-memory/MEMORY.md**

### The reproducer the bug never had
New integration test — fails on pre-plan code, passes now by construction:

```
it "auto-look survives a slow websocket connect" — login via HTTP, threadDelay
3000000 (three PlayerTicks — on old code the join has long since fired and the
narration is SendDropped), then connectWS, then receiveUntil isLookNarration
must succeed.
```

Also worth adding while in the file (cheap, same shape): witness ordering — A connects,
B logs in slow-connect style, A still receives "B has arrived."; B still receives the
lobby description. Optional; add on user approval, skip otherwise.

### MEMORY.md updates
- "Login always sends PlayerJoined — network decides new vs returning player" →
  PlayerJoined fires at websocket attach (AwaitingSocket → AwaitingJoin); network still
  decides new vs returning.
- "Server.Session removed — acConnections MVar replaces GameSessionRegistry" and
  "routes via acConnections" → acSessions phase map.
- One-authority list: is-connected = acSessions InGame phase.
- Departure detection line: gid ∈ acKnownPlayers ∧ gid has no InGame session.
- MVar-reads line: SFs read acSessions (same positions in the chain).
- Login-race entry: mark FIXED, point at this plan.
- Consolidation Decisions: acConnections/acPlayerMap replaced by acSessions
  (SessionPhase sum type in Server.App).

**Green because:** test-only + docs; the reproducer passes on the Step-3 tree.

---

## Explicit non-goals

- No reconnect-without-relogin feature: disconnect deletes the entry; a returning
  client re-logins (new sid) exactly as today. The InGame socket-replacement branch
  exists for socket churn on a live session, and is behavior-preserving with today's
  unconditional `acConnections` insert.
- No TTL/eviction machinery beyond the same-name login self-heal. Residual leak
  (a name that logged in once, never connected, never returned) is accepted, bounded,
  and noted next to the persistence debt.
- No changes to acKnownPlayers, acNextAgentId, the GameState chain, evaluators,
  narration, or the witness system.
- No wire-protocol or client changes; client-check/ts checks are unaffected throughout.

## Open items for user ruling before execution

1. `sessionGid`/`sessionSend` as exported total projections in Server.App (PInt
   precedent) — versus inline `case` at every site.
2. The optional witness-ordering test in Step 4.
3. `Data.Map.Strict.filter` qualification in loginHandler if the collision with the
   SashaPrelude list `filter` materializes.
