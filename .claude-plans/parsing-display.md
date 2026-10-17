# Parsing display (branch 27-parsing-display)

## Goal
The Parser tab in the web client shows the logged-in player's view: internal data for every agent in the player's scene, every object in that scene, and what happens when the player's typed sentence is parsed. The UX is worked out as we go. (user, 2026-10-17)

## Rulings
- sashamud-20 plans; sashamud-96 carries out tasks. (user, 2026-10-17)

## What exists today
- Wire: `AnalysisData (Map AnalysisViewport [RichText])` is a MessageFrom constructor, sasha/src/Model/WireProtocol.hs:44. AnalysisViewport is `Parser | State | Meta | Graphics | GameMap`, WireProtocol.hs:27. No site builds or sends AnalysisData.
- Client: web/apps/sasha-web/src/game/ViewportManager.ts:47 handleMessage has an AnalysisData case that replaces each keyed viewport's content through replaceRichText. Parser maps to the 'parser' viewport at ViewportManager.ts:19. RichText lines already render with no client change.
- Parse path: resolveCommands, sasha/src/Engine/Simulation/SignalNetwork.hs:427. A pure generator. `cmds` holds `lexify tokens cmdText >>= parseTokens` per session. A parse failure goes out as RepairRequest; a RepairedCommand rewrite parses again; each Sentence runs through `runEvalFor gid`. It returns `replies :: [Routed MessageFrom]` among its outputs.
- `lexify :: Lexer a -> Text -> Either Text a`, sasha-grammar/src/Grammar/Lexer.hs:98. `parseTokens :: [Lexeme] -> Either Text Sentence`, sasha-grammar/src/Grammar/Sentence.hs:20. Sentence and its sub-types derive Show and no JSON, sasha-grammar/src/Grammar/Parser/Composites/Model.hs:28-52.
- Scene contents: Scene `_sceneAgents :: Set (GID Agent)` and `_sceneObjects :: Set (GID Object)`, sasha/src/Model/Core.hs:233. Agent (Core.hs:216) and Object (Core.hs:206) derive Show. The player's scene comes from `_agentLocationMap`, Core.hs:441. The player's GID comes from sessionGid, sasha/src/Server/App.hs:121.
- Delivery: deliverNarrationIO, SignalNetwork.hs:537, writes `Routed sid msg` to acOutbound for each session.

## Old-code precedent
- sasha-server/src/MUD/GameLoop.hs:485: after each command the server builds the parse display (prettyShowSentence of the Sentence, or the parse error text), builds a snapshot from the post-command GameState for the acting agent, formats it per viewport, and sends AnalysisData to the sender only, ahead of the CommandResponse.
- sasha-engine/src/TopLevel.hs:195 prettyShowSentence: `show` of the Sentence with a newline and indent before each '('.
- sasha-engine/src/Telemetry/Format.hs:54 formatState: the State viewport as plain RichText lines with "=== Section ===" headers and "  (none)" for an empty section.
- sasha-engine/src/Telemetry/Snapshot.hs:125 captureAvailability and captureGIDNames: available actions and a GID-to-name map read from GameState.
- The old client used replaceRichText per viewport, the same as sashamud's client today.

## Decisions
- D1. RULED (user, 2026-10-17): the parse goes in the Parser tab. The agents and objects go in the State tab.
- D2. RULED (user, 2026-10-17): every parse stage shows: raw input, lexemes, the Sentence or the error, and every SLM repair (each rewrite, its parse result, and the final outcome).
- D3. RULED (user, 2026-10-17): every field of every agent and object in the player's scene shows, as pretty-printed JSON.
- D4. RULED (user, 2026-10-17): the State tab refreshes when there is a state change.
- D5. RULED (user, 2026-10-17): option C. An AppCtx MVar holds, per session, the State view that session was last sent. At the end of each PlayerTick a pure function compares each InGame session's current view with its last-sent view and returns AnalysisData State messages for the sessions whose view changed; the delivery step sends them and records them. The map holds only the last-sent view per session and is never a history log.
- D5 name. RULED (user, 2026-10-17): the AppCtx MVar is named acLastStateViews.
- D6. RULED (user, 2026-10-17): steps 1 and 3 get tests in a new spec file, SignalNetworkSpec.hs, in sasha/test beside the existing specs, picked up by hspec-discover and listed in the sasha.cabal test-suite other-modules.

## Steps
Step rule: every step builds and is green on its own. Any fix a step needs, including imports, exports, callers, instances and tests, lands in that step.

### Step 1. Parser view
File: sasha/src/Engine/Simulation/SignalNetwork.hs.
- Add prettyShowSentence, copied from old sasha-engine/src/TopLevel.hs:195.
- In resolveCommands, lex each GameCommand and each RepairedCommand rewrite with `lexify tokens`, then run parseTokens on the lexemes as a separate step, so the lexemes are available to the view. Today `cmds` and `repaired` use `lexify tokens text >>= parseTokens`.
- Add to `replies` one `Routed sid (AnalysisData (fromList [(Parser, lines)]))` for each GameCommand and each RepairedCommand, sent to the sender only (old sasha-server/src/MUD/GameLoop.hs:485). Lines are `plain` RichText lines (sasha/src/Model/RichText.hs:102) under old-style "=== Section ===" headers (old sasha-engine/src/Telemetry/Format.hs:54).
- GameCommand lines: "=== Input ===" with the raw text; "=== Lexemes ===" with `show` of the lexemes, or the lex error; "=== Sentence ===" with prettyShowSentence split into lines, or the parse error; when parsing failed, "=== Repair ===" with "  repair requested".
- RepairedCommand lines: "=== Input ===" with the original unparsed text and its ParseFailure; "=== Repair attempts ===" with each attempt in order (prior attempts from the pending repair, then this one): the rewrite, its lexemes, and its parse result, with the SLM name on this attempt; "=== Outcome ===" with one of: parsed, the sentence runs (with prettyShowSentence); failed, asking the SLM again (attempt n of 3); repair ended after n attempts; slm-absent; no repair pending.
- RULED (user, 2026-10-17): when a repaired rewrite parses, its sentence shows once, under "=== Outcome ===". The attempt row shows the rewrite and its lexemes.
- resolveCommands keeps its type. playerTickBlock already delivers `replies`.
- Tests (new file sasha/test/SignalNetworkSpec.hs, plus its entry in the sasha.cabal test-suite other-modules): resolveCommands with one InGame session. A GameCommand that parses yields a Parser AnalysisData reply to that session whose lines include the "=== Sentence ===" section with the prettyShowSentence lines. A GameCommand that fails to parse yields lines with the parse error and "  repair requested". A RepairedCommand whose rewrite parses, with a matching pending repair, yields lines with "=== Outcome ===" and the parsed outcome.
- SignalNetwork.hs exports whatever the tests call (resolveCommands, prettyShowSentence) if it does not already.

### Step 2. JSON instances for agents and objects
- sasha-grammar: ToJSON for Lexeme (Grammar/Lexer.hs:47), DirectionalStimulusMarker (Grammar/Parser/Atomics/Prepositions.hs:16), DirectionalStimulus (Grammar/Parser/Atomics/Nouns.hs:20), Determiner (Grammar/Parser/Atomics/Misc.hs:16), Adjective (Grammar/Parser/Atomics/Adjectives.hs:16), NounPhrase (Grammar/Parser/Composites/Nouns.hs:21), DirectionalStimulusNounPhrase (Grammar/Parser/Composites/Nouns.hs:34), the verb types DirectionalStimulusVerb, ImplicitStimulusVerb, AcquisitionVerb and DivestmentVerb, and VerbKey (Grammar/Parser/GCase.hs:21). VerbKey also gets ToJSONKey for the `Map VerbKey` field. Each type follows its existing deriving style: `deriving anyclass (ToJSON)` on Generic types, `deriving newtype (ToJSON)` on newtypes.
- sasha/src/Model/Core.hs: ToJSON for ActionManagement (:153), ActionManagementFunctions (:163), AgentKind (:199), Object (:206) and Agent (:216). GID (Model/GID.hs:15) and RichText (Model/RichText.hs:86) already have ToJSON.
- Before writing, the writer reads sasha-grammar.cabal and sasha.cabal for aeson in build-depends, and the SashaPrelude export list.
- No caller changes.
- RULED (user, 2026-10-17): every ToJSON added in this step has a matching FromJSON (VerbKey gets ToJSONKey and FromJSONKey). Every type that gains these instances is added to the JSON roundtrip properties in the existing sasha/test/JSONSpec.hs, with the Arbitrary instances that needs, following the repo's existing Arbitrary pattern (`#ifdef TESTING` in the source module, GenericArbitrary for sum and product types, `deriving newtype` for newtypes, arbitraryBoundedEnum for large enums, the constraint-solver-iterations pragma where GenericArbitrary needs it).

### Step 3. State view
- sasha.cabal: aeson-pretty in build-depends of the library and of the test suite. Precedent: quux/server/quux.cabal:259; encodePretty at quux/server/src/Embedded/Mock/JSONMachine.hs:38.
- aeson-pretty 0.8.10 is in the horizon-platform package set (user's `nix eval .#legacyPackages.x86_64-linux.aeson-pretty.version`, 2026-10-17). Step 3 needs no flake.nix change.
- sasha/src/Server/App.hs: AppCtx field `acLastStateViews :: MVar (Map SessionId [RichText])`. newAppCtx creates it with `newMVar mempty`.
- SignalNetwork.hs: `formatState :: GID Agent -> GameState -> [RichText]` (name from old sasha-engine/src/Telemetry/Format.hs:54). It finds the agent's scene through agentLocationMap. It renders "=== Agents ===" and, for each GID in sceneAgents, a line "  GID <n>" followed by encodePretty of that Agent split into `plain` lines; then "=== Objects ===" the same for sceneObjects; "  (none)" for an empty section. A missing location, scene, agent or object renders as a line naming the missing GID.
- playerTickBlock, after the result case: read acSessions again (as deliverNarrationIO does); build `views` as a Map from each InGame SessionId to `formatState gid gs'`; read acLastStateViews; send `Routed sid (AnalysisData (fromList [(State, view)]))` to acOutbound for each session whose view differs from its last-sent view; then write `views` into acLastStateViews whole. Writing the whole map each tick keeps one entry per live session, and ended sessions drop out.
- Tests (in sasha/test/SignalNetworkSpec.hs): formatState for a player in a scene with one other agent and one object yields lines with "=== Agents ===", a "  GID <n>" line for each agent, "=== Objects ===", and a "  GID <n>" line for the object. formatState for a scene with no objects yields "  (none)" under "=== Objects ===". The GameState is built from the existing defaults with lenses.
- SignalNetwork.hs exports formatState.

### Step 4. Wire shape matches the generated client
- RULED (user, 2026-10-17): the wire matches the generated client type. aeson encodes `Map AnalysisViewport [RichText]` as a JSON object, while the generated client.ts (aeson-typescript's Map instance, no sashamud override, API/TSClient.hs:43) types it as `[AnalysisViewport, Array<RichText>][]`, and the client loop at web/apps/sasha-web/src/game/ViewportManager.ts:101 iterates pairs. The Parser and State tabs stayed empty.
- sasha/src/Model/WireProtocol.hs: `AnalysisData (Map AnalysisViewport [RichText])` becomes `AnalysisData [(AnalysisViewport, [RichText])]`.
- sasha/src/Engine/Simulation/SignalNetwork.hs: every `AnalysisData (fromList [(Parser, ...)])` and `AnalysisData (fromList [(State, ...)])` becomes `AnalysisData [(Parser, ...)]` and `AnalysisData [(State, ...)]`.
- sasha/test/SignalNetworkSpec.hs: reply checks find the Parser entry in the list.
- No client edits. start-sashamud regenerates client.ts (flake.nix:423); the type stays `[AnalysisViewport, Array<RichText>][]`.
- Regression test sashamud-server/test-e2e/ParserViewSpec.hs, listed in the sasha-e2e-tests other-modules (sashamud-server/sashamud-server.cabal:57), following SlmRepairSpec's shape: open the Parser tab with Shift+4, type `look`, poll vp-parser-content for "=== Sentence ===". It runs under run-end-to-end.
- RULED (user, 2026-10-17): no e2e spec sends a modifier key, so ParserViewSpec opens the Parser tab by dispatching, through asyncJS, the keydown event that setupKeyboard (web/apps/sasha-web/src/game/ViewportManager.ts:198) listens for.

### Step 5. The client keeps each viewport's last lines
- RULED (user, 2026-10-17): the empty State tab is a client problem. The server sends the State view once on the first tick after login and again only when it changes (SignalNetwork.hs:303-307). Panels open only after login, and replaceRichText drops an update for a closed panel (ViewportManager.ts:133-146). The fix is in the client: it keeps the last AnalysisData lines per viewport and draws them when the panel opens.
- web/apps/sasha-web/src/game/ViewportManager.ts: a field holding the last RichText[] received for each ViewportId. The AnalysisData case stores the lines for each key before calling replaceRichText. When a viewport becomes active (toggleViewport, after rebuildLayout attaches the panel), the stored lines for that viewport are drawn with replaceRichText.
- Regression test in sashamud-server/test-e2e/ParserViewSpec.hs: a second `it` that, after waitConnected, dispatches the Shift+5 keydown (code 'Digit5', shiftKey true, on document, the same form as openParserTab) and polls vp-state-content until its text contains "=== Agents ===", with the same 15000 ms timeout and failure message form as pollParserViewport. No typed command is needed: the State view is sent on the first tick after login and the test checks it appears once the panel opens.
- The web checks ts-typecheck and ts-linting (flake.nix:716 onward) run on the client; the change passes both.

## Open issues
- Under start-sashamud, locally, the SLM repair fails on main and on this branch. llama-server answers a curl POST to http://localhost:8082/v1/chat/completions. In `nix flake check`, run-end-to-end passes SlmRepairSpec, but its browser loads the page from the harness's own http Warp server (SeleniumHarness.hs:318-337) and never goes through Caddy, https, the working-tree dist or startServer, so the check does not cover the start-sashamud path. The cause is not yet found. The empty State tab was explained and is fixed by Step 5.
- RULED (user, 2026-10-17): the fix for this lands with a test that runs in `nix flake check` and fails if it breaks again.
