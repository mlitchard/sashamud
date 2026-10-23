# Ctrl-c shuts down the whole stack

## Goal
Ctrl-c on start-sashamud stops every process the stack started. This also removes the cause of the 401 on deploy.

## His rulings
- RULED (user, 2026-10-17): quux is the model. Ctrl-c on quux's start-dev-servers shuts its whole stack down.
- RULED (user, 2026-10-17): sashamud-d0 plans; sashamud-1c executes.

## Evidence (2026-10-17)
- Snapshots A-D: after "sashamud is ready" and ctrl-c, the start shell and llama-server exit.
  sasha-server, caddy, the authentik VM and postgres keep running with parent PID 1.
  .devpids still exists. Nothing prints after ^C. The SIGINT trap does not run.
- stop-sashamud run by hand clears every stack process and frees port 8081.
- The 401: a sasha-server left by an earlier ctrl-c held 8081. The new server minted its token,
  failed to bind (server.log:20), and the deploy reached the old server, whose acSessions had no
  entry for the token (sasha/src/Server/Server.hs:118-123).
- Tests pass because run-sasha-tests runs in a fresh VM and never deploys DSL.

## What exists today
- sashamud teardown, flake.nix:281-301: trap set before `${upDown.up}`; trap body `set +e; stop-sashamud`.
- quux teardown, quux/utils.nix:34-59: trap set after `${upDown.up}`; trap body runs down,
  `kill -9 $(cat .devpids)`, then the `ps faux | grep quux` sweep.
- MEMORY.md:269: "The teardown trap is installed before `up`."
- Why the trap does not fire is not confirmed from source. The step 1 check settles it.

## Decisions
1. Trap placement. RULED (user, 2026-10-17): follow quux. Follow quux: install the trap after `${upDown.up}`. This reverses MEMORY.md:269.
2. Trap body. RULED (user, 2026-10-17): keep `set +e; stop-sashamud`. Keep `set +e; stop-sashamud`. stop-sashamud already kills .devpids and every
   stack process (flake.nix:456-471).

## Steps
Step rule: every step builds and is green on its own; any fix a step needs lands in that step.

Step 1 (sashamud-1c): edit teardown in flake.nix per decisions 1 and 2. A Sonnet writer updates MEMORY.md:269 to match.
Check: the user enters a fresh devshell, runs start-sashamud, waits for "sashamud is ready", and
presses ctrl-c. sashamud-1c confirms .devpids is absent and no stack process remains in ps.
