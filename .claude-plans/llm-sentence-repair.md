# LLM sentence repair

Status (2026-10-16): steps 1-5 are done, green and committed. The flake check is green.

## Goal

When a player's sentence fails to parse, a language model rewrites it into a
sentence the parser accepts. The rewritten sentence goes through the parser
again. If that parse also fails, the player gets a failure message. The
design is not tied to one model or one vendor.

## His rulings

- A small language model may be enough for the rewrite. (user, 2026-10-15)
- If Ollama is used, it runs client side, on the player's machine. The
  browser connects to the model installed on the host. (user, 2026-10-15)
- Web research is allowed for this task, done by Opus. (user, 2026-10-15)
- The old sasha grammar (/home/mlitchard/gitlab/sasha/) is the grammar sashamud builds out. (user, 2026-10-15)
- The target machine is the player's gaming PC with a video card. (user, 2026-10-15)
- This work is an experiment. (user, 2026-10-15)
- Players need only Linux. Nix is never required of players. (user, 2026-10-15)

## Flow (confirmed by user, 2026-10-15)

1. The player types a sentence. The server lexes and parses it, and it fails.
2. The server sends the failed sentence to the player's client.
3. The client sends llama-server on the player's machine the failed sentence,
   an instruction to rewrite it as a game command, and the GBNF grammar as
   the output constraint.
4. The model replies with a plain sentence. The grammar limits which words
   it can use and their order.
5. The client sends that sentence to the server as an ordinary command.
6. The server parses it. If it parses, it runs. If it fails, the player gets
   the failure message.

The server never rewrites a sentence and never calls a model.

## What exists today

- Parse failure aborts the whole tick. `runEvalFor`
  (sasha/src/Engine/Simulation/SignalNetwork.hs:352) does `throwError err`
  on a lexify or parseTokens failure. `resolveCommands` (:376) folds every
  player's command into one computation with `mapM_`, and `composeTick`
  (:234) runs it. `GameComputation` is `ExceptT Text (GameStateT m)`
  (sasha/src/Model/Core.hs:464). `playerTickBlock` (:198-232) handles
  `Left err` by writing "Tick computation failed" to stderr. No player gets
  narration that tick, and the player who typed the sentence gets no message.
- Wire types. `MessageFrom` = SessionAck | GameNarration Narration |
  CommandResponse [RichText] | ChatMessage Text | SystemMessage Text | Pong |
  AnalysisData (sasha/src/Model/WireProtocol.hs:35). `MessageTo` = Ping |
  GameCommand Text (sasha/src/API/Types.hs:32). Both generate TypeScript via
  `derivingTypeScriptDefinition` (Types.hs:39, WireProtocol.hs:48) into
  web/packages/type-gen-output/src/client.ts.
- Client. `ViewportManager.handleMessage`
  (web/apps/sasha-web/src/game/ViewportManager.ts:47) switches on
  `msg.tag`. `GameConnection.sendCommand`
  (web/apps/sasha-web/src/game/GameConnection.ts:63) sends
  `{ tag: 'GameCommand', contents: text }`. The client has no settings
  store; the session token sits in sessionStorage
  (web/apps/sasha-web/src/main.ts:6).
- Grammar today. `Sentence = Imperative Imperative`
  (sasha-grammar/src/Grammar/Parser/Composites/Model.hs:52), parsed with
  Earley (`fullParses`, first parse wins) in Grammar/Sentence.hs. The lexer
  uppercases input and turns every unknown word into `PLAYERNAME`
  (Grammar/Lexer.hs:127). Word lists are HashSets per category under
  Grammar.Parser.Atomics.Semantics.*.
- AppCtx holds `acHttpManager`; sasha.cabal has http-client and aeson. The
  server makes no model calls under this plan.
- Tests in CI. `grammar-tests` (sasha-grammar/sasha-grammar.cabal:67-81, `hs-source-dirs: test`, no other-modules) runs as the flake check `run-grammar-tests` (flake.nix:709-724) and in CI as `checks:run-grammar-tests` (.gitlab-ci.yml:111). sasha-grammar/test exists, holding Main.hs, Test/Lexer.hs, Test/Arbitrary/Verbs.hs and Test/Parser/Atomics/Verbs.hs.
- The e2e specs build as the executable `sasha-e2e-tests` (sashamud-server/sashamud-server.cabal:57). test-e2e/Spec.hs is hspec-discover. Each spec module is also listed in the executable's other-modules (:62-69). The flake check `run-end-to-end` (flake.nix:795) runs it inside a NixOS VM through the script `sasha-e2e-wrapped`, and CI runs that check as `checks:run-end-to-end` (.gitlab-ci.yml:101).
- How the e2e tests start processes. `withServer` (sashamud-server/test-e2e/SeleniumHarness.hs:129) starts the game server inside the test executable with `testWithApplication` (:161). `sasha-e2e-wrapped` (flake.nix:797-820) starts the Selenium server in the background, polls `localhost:4444` until it answers, runs the tests, then kills it.
- The TypeScript deriving library is the package `aeson-typescript`, imported as `Data.Aeson.TypeScript (derivingTypeScriptDefinition)` (sasha/src/API/Types.hs:17). The flake overlay supplies it to the whole Haskell package set (flake.nix:129-132), and sasha-grammar is built in that set (flake.nix:98). sasha-grammar's build-depends (sasha-grammar.cabal:57-65) lists neither aeson nor aeson-typescript.
- Quux puts Arbitrary instances for types from another package in an orphan module in the test folder: quux/server test/ArbitraryOrphans.hs, `{-# OPTIONS_GHC -Wno-orphans #-}`, `module ArbitraryOrphans () where`. Sasha's tests recompile only sasha's sources, so `#ifdef TESTING` cannot reach types defined in sasha-grammar.
- Vocabulary today: verbs look, get, drop. Shapes: look, look at X, get X, drop X (sasha-grammar/src/Grammar/Parser/Composites/Rules.hs:152). Nouns ball, floor. Adjectives small, white, red. Determiners a, the. Getting the ball narrates "You pick up the red ball." (sashamud-world/src/2/Lobby/4-get-drop-ball.dsl:17).
- A sentence that parses but names no object it can act on gets narration
  for the actor. GET looks the noun up in the scene's `objectSemanticMap`
  and DROP looks it up in `globalSemanticMap`, keeping only objects in the
  actor's inventory (sasha/src/Engine/ActionDiscovery/Instances.hs:174,
  :281). A miss adds "You don't see that here." (GET) or "You don't have
  that." (DROP) to the actor's actionConsequence through
  `modifyAgentNarration` (sasha/src/Engine/Resolution/Perception.hs:46).
  Integration test: sashamud-server/test/Integration/LoginLogoutSpec.hs:612
  sends `get the white ball` and waits for "You don't see that here." A
  noun that matches more than one object still does
  `throwError ("Which " <> nounText <> "?")`.
- Object semantic map. `Scene._objectSemanticMap` and
  `World._globalSemanticMap` are both `Map Text (Set (GID Object))`
  (sasha/src/Model/Core.hs:237, :274). The builder fills both, keyed by
  noun text, when an object is placed in a scene
  (sasha/src/DSL/Builder.hs:235). The adjective in a noun phrase picks
  among the matches with `findMatchingObject`. Both maps live in GameState.

## Old-code precedent

- Synonyms and alternate spellings live in the lexer: several input strings
  map to one lexeme with `<|>`. Examples in
  /home/mlitchard/gitlab/sasha/sasha-grammar/src/Grammar/Parser/Lexer.hs:
  `close = CLOSE <$ symbol "CLOSE" <|> CLOSE <$ symbol "SHUT"` (:335),
  `NORTH <$ symbol "N"` (:284), `TEAOMATIC <$ symbol "TEA-O-MATIC"` (:81).
  /home/mlitchard/gitlab/sasha/docs/subsystems/Parser.md:119 "Synonyms
  handled at lexer level". Known misspellings use the same pattern.
- Old sasha grammar: `parseTokens :: VocabConfig -> [Lexeme] -> Either Text
  Sentence` (sasha-grammar/src/Grammar/Parser.hs:20). The Lexeme type is a
  closed enum deriving Bounded, Enum (sasha-core/src/Model/Parser/Lexer.hs:22).
  Imperative has sixteen phrase kinds plus DirectedImperative
  (sasha-core/src/Model/Parser/Composites/Verbs.hs).
- Delivering a reply to one session only: dslTickSF
  (SignalNetwork.hs:176-196) reports back only to the submitter.
- No precedent for GBNF generation or for calling a model.

## Research findings (Opus web reports, 2026-10-15)

- llama-server sends CORS headers. `--cors-origins` defaults to `*`;
  `--cors-origins https://sashamud.net` limits it to one origin.
- `/v1/chat/completions` accepts a GBNF `grammar` field (read in
  tools/server/server-common.cpp) and applies the model's chat template.
  `grammar` and `json_schema` cannot be combined.
- The default port differs by version (README 9931, NixOS wiki 8080). Pass
  `--port` explicitly. `--api-key` is optional.
- Models load with `-hf <repo>[:quant]`, for example Qwen/Qwen3-1.7B-GGUF,
  ggml-org/SmolLM3-3B-GGUF, bartowski/Llama-3.2-3B-Instruct-GGUF,
  ggml-org/gemma-4-E4B-it-GGUF.
- nixpkgs: `llama-cpp`, `llama-cpp-vulkan`; CUDA via
  `llama-cpp.override { cudaSupport = true; }`. NixOS module
  `services.llama-cpp`. Prebuilt binaries for Windows, macOS and Linux with
  CUDA, Vulkan, Metal and ROCm on the GitHub releases page.
- The grammars README warns of performance gotchas and recommends `x{0,N}`
  over chained `x?`.
- Safari blocks https pages calling http://localhost. Chrome 142+ and
  Firefox 151+ ask the player for local-network permission. Whether
  llama-server needs anything beyond CORS for Chrome's check is unknown.
- Small models: Qwen3 0.6B/1.7B/4B (Apache-2.0), Llama 3.2 1B/3B (IFEval
  59.5/77.4), SmolLM3-3B (IFEval 76.7), Gemma 4 E2B/E4B, Phi-4-mini.
- llama-server applies the grammar from the first token (llama.cpp issue #12276), so a thinking model must have thinking off: per request `"chat_template_kwargs": {"enable_thinking": false}`, or server-wide `--reasoning off`.
- llama.cpp build 9350 accepted an invalid GBNF, returned HTTP 200 and generated with no constraint (issue #24144). PR #24154 fixed it.
- The old sasha grammar is flat: two sentence forms (Imperative, and `AgentName , Imperative`), one fixed argument frame per verb class, noun phrases of at most one determiner and one adjective, and no recursion. Some words sit in several categories (PLANT, GET, OPEN, ASK, WITH, FROM); the rule position decides which applies. The model's hard part is mapping what the player meant onto a verb class.

## Decisions

1. RULED (user, 2026-10-15): llama-server on the player's machine, with
   output constrained by a GBNF grammar the server generates from the word
   lists the parser reads.
2. RULED (user, 2026-10-16): the GBNF is generated in sasha-grammar per
   failed sentence.
   2a. What the narrowing keeps: lexemes recognized in the sentence, the
       objects and agents in the player's scene, or both.
       Narrowing works on whole words. A word found in the sentence stays
       in every word list it belongs to: PLANT is a divestment verb and an
       adjective, and "plant the pot plant in the plant pot" uses it as a
       noun too. Verb roles stay complete, since the intended verb is often
       absent ("i want" -> GET). Narrowing by scene contents reads GameState.
       RULED (user, 2026-10-16): the narrowing keeps the words recognized in the sentence, agents included. The verbs stay complete. A list keeps only the words the sentence names. A list the sentence names no word from keeps its full list, so no GBNF rule is ever empty. A player name counts as recognized when a PLAYERNAME token from the lexer matches a name in the known-player list, comparing in uppercase because the lexer uppercases its input.
3. RULED (user, 2026-10-16): resolveCommands lexes and parses each command
   before building the computation. Parsed sentences go into the
   computation. Failures return as IO-phase data beside pings, and the IO
   phase sends the MessageFrom constructor `RepairRequest` (user-named,
   2026-10-16) to that session, carrying the failed sentence and its GBNF.
   Fields: `UnparsedSentence` and `Gbnf` (user-approved, 2026-10-16).
4. RULED (user, 2026-10-16): a rewritten sentence that fails to parse gets
   the failure message. The server logs the unparsed sentence, the rewrite
   and the GBNF. A rewrite is never sent for repair again. The MessageTo
   constructor is `RepairedCommand UnparsedSentence Text SlmName` (see decisions 10, 23). Amended by decision 21 (user, 2026-10-16): three attempts, then the failure message; the failure row in repair_failures holds the record.
5. RULED (user, 2026-10-16): cloud LLM access will be offered later. The
   first iteration uses a locally installed small model. A player with no
   reachable local model gets the failure message.
6. RULED (user, 2026-10-16): a fixed default `http://localhost:<port>`
   built into the client. The port comes from the same flake let binding
   the dev shelper passes to `--port`. The model is chosen when the player
   starts llama-server (`-hf`). Note (user, 2026-10-16): the slm tag the client sends comes from the build-time slmName (decision 23), so it assumes the player runs the pinned model (decision 12). Reading the model name from llama-server's reply is a later change.
7. Misspellings: SETTLED by old code. Known misspellings are lexer
   alternatives, `X <$ symbol "X" <|> X <$ symbol "MISSPELLING"`.
8. RULED (user, 2026-10-16): `Gbnf` and `UnparsedSentence` live in
   sasha-grammar, which gains aeson and `aeson-typescript` so
   the instances sit beside the types. sasha imports them. This keeps the
   dependency one way (sasha-grammar <- sasha) and avoids a circular import.
9. RULED (user, 2026-10-16): the GBNF's player-name rule lists the names in
   acKnownPlayers, the is-a-player authority, passed to the pure generator
   as data.
10. RULED (user, 2026-10-16): the MessageTo constructor is
    `RepairedCommand UnparsedSentence Text SlmName`. When a rewrite fails, the
    server regenerates the GBNF from the unparsed sentence and logs the
    sentence, the rewrite and the GBNF. Amended by decision 23 (user, 2026-10-16).
11. RULED (user, 2026-10-16): testing has no manual steps. CI and local
    runs start llama-server automatically. The test model is a pinned
    fixed-output fetch; tests run the CPU build at temperature 0.
12. RULED (user, 2026-10-16): the model is Qwen3-1.7B, for players and for CI. Pinned file: repo `Qwen/Qwen3-1.7B-GGUF`, commit `90862c4b9d2787eaed51d12237eafdfe7c5f6077`, file `Qwen3-1.7B-Q8_0.gguf`, URL `https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/90862c4b9d2787eaed51d12237eafdfe7c5f6077/Qwen3-1.7B-Q8_0.gguf`, SHA256 `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a`. Thinking is off on every request. A separate session sets up the model.
13. RULED (user, 2026-10-16): the instruction, sent as the system message: "Rewrite the player's sentence as a command for a text adventure game. Keep what the player meant. Reply with the command only." The failed sentence is the user message. Amended by decision 22 (user, 2026-10-16).
14. RULED (user, 2026-10-16): the step 4 test sentence is `pick up the red ball`. The rewrite must be `get the red ball`. The test waits for the narration "You pick up the red ball." The narration is the witness, and the client shows the player only the narration.
15. SETTLED (user, 2026-10-16): the player-name list is never empty. A RepairRequest goes only to a joined player, whose name is in acKnownPlayers. Amended (user, 2026-10-16): acKnownPlayers gains a new player only in executeJoinIO, after the tick's computation, so a player whose join and first command land in the same tick is missing from it. The GBNF's name list is the names in acKnownPlayers plus the names of this tick's NewPlayerJoined results (playerTickBlock, sasha/src/Engine/Simulation/SignalNetwork.hs). Found by step 4's e2e run, where llama-server rejected an empty `player-name ::=` rule.
16. RULED (user, 2026-10-16): when the client gets no answer from llama-server (not running, wrong port, blocked, error, timeout), it sends RepairedCommand with the player's original sentence and slm-absent. The server parses it, it fails, and the player gets the failure message. In step 3, before any model call exists, the client always does this.
17. RULED (user, 2026-10-16): the client reads the port at build time as `VITE_SLM_PORT`, set from `slmPort`. sashamud-85 wires the flake: dev shell, the `web` derivation the VM tests serve, and start-sashamud's build. The client code that reads it is part of step 4.
18. RULED (user, 2026-10-16): module `Grammar.Gbnf` holds `Gbnf`, `UnparsedSentence` and `generateGbnf`.
19. RULED (user, 2026-10-16): two new tables and an `slm` table, after quux's
    `roles` (quux migrations/build/08-roles.sql:24).
    - slm (slm_id SERIAL PRIMARY KEY, name TEXT UNIQUE NOT NULL). Rows:
      'qwen-Qwen3-1.7B-Q8_0', 'slm-absent'. A new model is a new row.
    - repair_failures (failure_id SERIAL PRIMARY KEY, scene TEXT NOT NULL,
      actor INT NOT NULL REFERENCES users(user_id), unparsed_sentence TEXT
      NOT NULL, parse_error TEXT NOT NULL, attempts TEXT[] NOT NULL,
      attempt_errors TEXT[] NOT NULL, slm_id INT NOT NULL REFERENCES
      slm(slm_id)).
    - repair_successes (success_id SERIAL PRIMARY KEY, scene TEXT NOT NULL,
      actor INT NOT NULL REFERENCES users(user_id), unparsed_sentence TEXT
      NOT NULL, rewrite TEXT NOT NULL, slm_id INT NOT NULL REFERENCES
      slm(slm_id)).
    - scene holds the SceneLabel (stable across world reloads; Core.hs:274
      _declaredSceneGIDs). actor is written as Mid AuthenticatedUser
      (sasha/src/Model/Mid.hs:20, API/Types.hs:52), quux's Mid pattern.
    - slm_id is filled by `(SELECT slm_id FROM slm WHERE name = ?)`, after
      quux rolePermissionsQuery (quux test/Initialize.hs:126).
    - Reads and writes run through `withResource (acDbPool ctx)` in the IO
      phases of playerTickBlock (SignalNetwork.hs:198).
20. RULED (user, 2026-10-16): repair_successes is a record for study. The
    parse flow never reads it. A parse failure goes straight to
    RepairRequest (decision 3). A lookup is a future decision.
21. RULED (user, 2026-10-16): three attempts per failure, driven by the
    server. AppCtx gains acPendingRepairs (user-named), an MVar keyed by
    SessionId holding one repair in progress per session, after
    acOidcStates (Server/App.hs:149). A RepairedCommand that fails to parse
    sends a new RepairRequest until the third attempt. After the third
    failure the server writes the repair_failures row and sends the
    failure message. The first RepairedCommand that parses runs and is
    written to repair_successes.
22. RULED (user, 2026-10-16): attempts two and three carry the earlier
    rewrites, each with its parser error, in the RepairRequest. The client
    adds them to the user message.
23. RULED (user, 2026-10-16): the MessageTo constructor is
    `RepairedCommand UnparsedSentence Text SlmName`. SlmName is a newtype
    over Text holding the slm row name, in sasha/src/API/Types.hs beside
    MessageTo. The client sends the name of the model that answered, or
    'slm-absent' with the player's original sentence when llama-server
    gave no answer (see decision 16). A slm-absent repair ends at once:
    the sentence fails, the row is tagged slm-absent, the player gets the
    failure message. The client's model name comes from a flake let
    binding, slmName = "qwen-Qwen3-1.7B-Q8_0", passed to both Vite builds
    the way slmPort is.
24. RULED (user, 2026-10-16): names repair_failures, repair_successes,
    SlmName.
25. RULED (user, 2026-10-16): names and shapes.
    - PendingRepair: the value held per session in acPendingRepairs, in
      sasha/src/Server/App.hs beside AppCtx. It holds the failed sentence,
      its ParseFailure, and the attempts so far.
    - RepairAttempt: one rewrite with its ParseFailure.
    - ParseFailure: newtype over the parser's error text (lexify and
      parseTokens return Either Text). Named after JoinFailure.
      Megaparsec's ParseError stays out of scope by explicit imports.
    - RepairAttempt and ParseFailure live in sasha/src/API/Types.hs beside
      SlmName, since they travel on the wire.
    - The MessageFrom constructor is
      `RepairRequest UnparsedSentence ParseFailure Gbnf [RepairAttempt]`.
      The list is empty on the first attempt and holds the earlier
      attempts on attempts two and three.
26. RULED (user, 2026-10-16): migrations/build/04-repair.sql seeds the two
    slm rows, 'qwen-Qwen3-1.7B-Q8_0' and 'slm-absent', after quux's roles
    seed (quux migrations/build/12-factory-reset.sql:41). This is a
    narrow exception to "migrations are schema only", which exists for
    account rows that need createAccount's signature. A new model is a
    new migration that inserts its row.

## Steps

The step rule: every step builds and is green on its own. Any fix a step
needs, including imports, exports, callers, instances and tests, lands in
that step. No step relies on a later step to fix it.

1. Parse failure stays with the player (decision 3).
   - resolveCommands (sasha/src/Engine/Simulation/SignalNetwork.hs:376)
     lexes and parses each command before building the computation. Parsed
     sentences go into the computation; failures return as IO-phase data
     beside pings.
   - Both callers of runEvalFor change in this step: resolveCommands
     (:383) and the auto-look for joined players in composeTick (:240,
     `runEvalFor gid "look"`).
   - resolveCommands returns the parse failures as `(SessionId, ParseFailure)` pairs beside pings, following the generator pattern. The auto-look in composeTick parses `look` the same way; a failure there throws, as it does today. playerTickBlock sends each failure as SystemMessage before `case result`, the same way pings go out (:219-220), so a failure reaches the player even when the tick fails. ParseFailure (decision 25) is defined in this step, in sasha/src/API/Types.hs, with its JSON and TypeScript instances, `Arbitrary` under `#ifdef TESTING`, and a prop line in JSONSpec.
   - Test: a test-e2e spec following LookWitnessSpec
     (sashamud-server/test-e2e/LookWitnessSpec.hs,
     `webDriverTestWithClient ctx ["witness"]`). One player sends `pick up the red ball` (PICK and UP lex as player names, and the parse fails); the other player's narration still arrives; the
     sender sees the failure text. The test sentence must fail to lex or parse. A sentence such as
     `get the white ball` parses and gets the miss narration, so it does not
     exercise this step. The spec is registered with the other
     test-e2e specs in this step. Registered by adding the module to the other-modules of `sasha-e2e-tests` (sashamud-server.cabal:62-69). CI runs it through `checks:run-end-to-end`.

2. GBNF generator in sasha-grammar (decisions 2, 7, 8).
   - sasha-grammar defines the newtypes `Gbnf` and `UnparsedSentence`, with
     ToJSON/FromJSON and TypeScript definitions derived beside them.
     sasha-grammar.cabal gains aeson and `aeson-typescript` in build-depends. The
     flake already supplies it (flake.nix:129-132). No flake change.
   - A pure function builds a `Gbnf` from the word lists, the phrase shapes
     in Grammar/Parser/Composites/Rules.hs, and a list of player names
     passed in as data.
   - Module `Grammar.Gbnf` (decision 18) goes into exposed-modules. sasha-grammar has `NoImplicitPrelude` and no prelude module, so names are imported explicitly from base, as in test/Test/Lexer.hs. The module needs the `TemplateHaskell` pragma for `derivingTypeScriptDefinition`. The newtypes derive Eq, Ord, Show, Generic, NFData, FromJSON and ToJSON, which MessageFrom requires.
   - Words come from each HashSet through `toLexeme` and Lexeme's derived Show, which gives uppercase text such as `BALL`. The lexer uppercases its input. The Earley rules can't be inspected, so `generateGbnf` writes out the shapes of `imperativeRules` (Rules.hs:152) itself, including `LOOK AT <player name>` (:139-144). A shape added to Rules.hs needs the same addition in `generateGbnf`.
   - The spec is test/Test/Gbnf.hs exporting `spec`. hspec-discover finds it (test/Main.hs:1), and grammar-tests needs no cabal change.
   - The spec goes into the existing sasha-grammar/test folder. CI runs it through `checks:run-grammar-tests`.
   - Test: the generated text names every word in each word list, every
     phrase shape, and each player name passed in (the test passes at least one name; see decision 15).

3. RepairRequest and RepairedCommand (decisions 3, 4, 9, 16, 19-26).
   - MessageFrom (sasha/src/Model/WireProtocol.hs:35) gains
     `RepairRequest UnparsedSentence ParseFailure Gbnf [RepairAttempt]` (decision 25). MessageTo
     (sasha/src/API/Types.hs:32) gains
     `RepairedCommand UnparsedSentence Text SlmName` (decision 23).
   - Model/WireProtocol.hs and API/Types.hs each add `import ArbitraryOrphans ()` inside their existing `#ifdef TESTING` block, so their GenericArbitrary derivings find the new instances (quux src/Model/Channel.hs:31-35). SignalNetwork's explicit import lists gain the new constructors.
   - The step 1 spec changes in this step. The sender now receives RepairRequest carrying the sentence where step 1 sent SystemMessage.
   - resolveCommands classifies RepairedCommand alongside GameCommand.
   - A GameCommand that fails to parse yields RepairRequest, with the GBNF
     built from the word lists and the names in acKnownPlayers (`known`,
     already read in playerTickBlock).
   - A RepairedCommand that fails to parse follows decision 21: a new RepairRequest carrying the earlier attempts (decision 22) until the third failure, then the repair_failures row and the failure message as SystemMessage. A RepairedCommand tagged slm-absent ends the repair at once (decision 23).
   - ViewportManager.handleMessage (web/apps/sasha-web/src/game/ViewportManager.ts:47) gains a RepairRequest case that sends RepairedCommand with the original sentence and slm-absent through GameConnection (decision 16). GameConnection gains a send for RepairedCommand; its sendCommand sends only GameCommand and Ping today (GameConnection.ts:63-70).
   - Arbitrary instances for UnparsedSentence and Gbnf go in a new sasha/test/ArbitraryOrphans.hs, following quux/server test/ArbitraryOrphans.hs: `{-# OPTIONS_GHC -Wno-orphans #-}`, `module ArbitraryOrphans () where`. The module is added to sasha-tests other-modules. sasha/test/JSONSpec.hs imports `ArbitraryOrphans ()` and gains the two `prop` lines.
   - Migration migrations/build/04-repair.sql creates slm, repair_failures
     and repair_successes (decision 19) and seeds the two slm rows
     (decision 26), with DROP ... IF EXISTS first, as 00-auth.sql does.
     migrations/rollback/95-repair.sql drops them, so MigrationSpec's
     "only schema_migrations remains" stays green.
   - RepairedCommand carries SlmName (decision 23). AppCtx gains
     acPendingRepairs, set up in newAppCtx (Server/App.hs:156). The
     attempt loop, the context on attempts two and three, and the row
     writes follow decisions 21 and 22.
   - Before writing the row writes, the executor quotes where the session's account id (Mid AuthenticatedUser) is held at tick time. decision 19's actor column needs it, and acSessions holds SessionPhase.
   - SlmName and RepairAttempt get JSON and TypeScript
     instances beside MessageTo, and prop lines in JSONSpec. SlmName gets
     ToField/FromField by newtype deriving, the way Mid does. SlmName and RepairAttempt derive `Arbitrary` under `#ifdef TESTING` in API/Types.hs, the existing sasha pattern. ParseFailure already has it from step 1.
   - Tests: a sasha test writes one row to each table and reads it back,
     after quux's verifyLogin read-back (quux test/Quux/EndpointsSpec.hs:1556).
   - Tests: the JSON props; an e2e spec where the client's step 3 handler answers a RepairRequest with slm-absent, and the sender sees the failure text. The e2e spec is registered in `sasha-e2e-tests` other-modules.

4. Client calls llama-server, with dev and CI wiring (decisions 5, 6, 10, 12-17, 22, 23).
   - Already on the branch (setup session, 2026-10-16): let bindings `slmPort = "8082"`, `slmModel` (fetchurl of the decision 12 URL and SHA256) and `llamaCppCuda` (`pkgsCuda.llama-cpp` from nixpkgs imported with `allowUnfree`); packages `llama-cpp-cuda` and `slm-model`; shelpers `start-slm-model` (runs `llama-server -m $SLM_MODEL --port ${slmPort} -ngl 99 --reasoning off`) and `stop-slm-model`, called from start-sashamud and stop-sashamud. The pinned nixpkgs carries llama-cpp 9925, and the CPU `pkgs.llama-cpp` for CI is the same version. 9925 includes the PR #24154 fix: it rejects an invalid GBNF with HTTP 400 (step 4 e2e run).
   - llama-cpp 9925 has no `--cors-origins` flag. Its built-in CORS handling echoes the Origin header and allows GET and POST, which serves the client, so `start-slm-model` stays unchanged.
   - The client reads `import.meta.env.VITE_SLM_PORT` (decision 17). sashamud-85 wires it into the `web` derivation (flake.nix:580), start-sashamud (flake.nix:410) and the dev shell before this step.
   - On RepairRequest the client POSTs to `http://localhost:<port>/v1/chat/completions` with the decision 13 instruction as the system message, the unparsed sentence as the user message, the GBNF in `grammar`, `temperature: 0` and `chat_template_kwargs: {enable_thinking: false}`. It reads `choices[0].message.content` and sends RepairedCommand through GameConnection (web/apps/sasha-web/src/game/GameConnection.ts:63). A failed fetch sends RepairedCommand with the original sentence and slm-absent (decision 16).
   - The client sends RepairedCommand with `import.meta.env.VITE_SLM_NAME`, set from the `slmName` let binding (decision 23). sashamud-85 wires `slmName` and `VITE_SLM_NAME` the way it wired `VITE_SLM_PORT`, before this step. It sends that name, or
     'slm-absent' and the original sentence when the fetch fails. On a
     RepairRequest carrying earlier attempts, it adds them to the user
     message.
   - `sasha-e2e-wrapped` (flake.nix:797-820) starts llama-server in the background with `--port`, llama-server's built-in CORS handling, since the test page's origin `http://127.0.0.1:<free port>` changes every run (SeleniumHarness.hs:337), and `-m` on the model file. It polls the port until llama-server answers, runs the tests, and kills it at the end, the same way it handles Selenium. `withServer` runs inside that VM, so this one change covers both. No manual steps. The script runs the CPU `pkgs.llama-cpp` by store path, with `slmModel`.
   - Test: an e2e spec drives the real client in the browser and sends `pick up the red ball`. It waits for "You pick up the red ball." (decision 14). It is registered in `sasha-e2e-tests` other-modules. The CPU model's speed in CI is unknown until the first run. It uses `webDriverTestWithPage` (SeleniumHarness.hs:318), which loads the built client. `webDriverTestWithClient` talks over a raw socket and never loads ViewportManager. The spec is SlmRepairSpec, which replaces step 3's SlmAbsentSpec.

5. Narrowing (decision 2a).
   - `generateGbnf` gains the failed sentence as an argument: `generateGbnf :: UnparsedSentence -> [PlayerName] -> Gbnf`. It lexes the sentence with `lexify tokens`. Each non-verb list keeps the words whose lexeme appears in the result, or its full list when none do. The player-name rule keeps the known names that match a PLAYERNAME token, or every known name when none match.
   - Callers change in this step. In `playerTickBlock` (SignalNetwork.hs), `resolveCommands` takes the name list in place of one tick-wide `Gbnf`, and builds a GBNF for each failed sentence: on the first RepairRequest, and again on the second and third attempts. sasha-grammar/test/Test/Gbnf.hs passes a sentence.
   - Tests:
     - `pick up the red ball` keeps BALL, RED and THE.
     - A sentence naming PLANT (once the vocabulary has it) keeps PLANT in every list it belongs to.
     - A sentence naming no word from a list leaves that list complete.
     - A sentence naming a known player keeps that name. One naming none keeps every known name.
     - The verbs are always complete.
