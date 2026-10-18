# Arges deploy: fresh database, live DSL, SLM client

Written 2026-10-18. Planner: sashamud-14. Executor for the deploys repo: deploys-04.

## Goal

Deploy the current sashamud to arges with a fresh database. The server starts empty, the world arrives through `deploy-dsl`, and the web bundle carries the SLM client.

## Rulings

- RULED (user, 2026-10-18): drop the database on arges, no backup.
- RULED (user, 2026-10-18, deploys brief): `SASHA_OIDC_REDIRECT_URI` stays `https://sashamud.net/api/auth/callback`.
- RULED (user, 2026-10-18, deploys brief): the arges unit sets the bootstrap token file; mirror what the sashamud VM tests use.
- RULED (user, 2026-10-18, deploys brief): nothing on arges calls qwen. The browser calls `http://localhost:8082` on the player's machine. The web bundle with 8082 built in ships through the `sasha` input.
- RULED (user, 2026-10-12, deploys brief): `nix run .#arges switch` runs after the deploys changes are committed.

## What exists today

sashamud (branch deploy-slm-changes):
- `flake.nix:552` `sasha-server` wrapper sets defaults for `SASHA_DB_CONNSTR`, `SASHA_MIGRATIONS_DIR` (store path of `migrations/`), `SASHA_WORLD_DIR`, `SASHA_BOOTSTRAP_WIZARD` (`wizard`), the OIDC vars, `SASHA_ENVIRONMENT` (`production`).
- `sasha/src/Server/Server.hs:151-178` reads those vars plus `SASHA_WEB_PORT` and `SASHA_BOOTSTRAP_TOKEN_FILE`. Migrations run at process start (`Server.hs:156`, `Server/Migration.hs:14-21`). A fresh database receives every script under `migrations/build`, including `04-repair.sql` with the seeded `slm` rows.
- With the token file set, the server polls for the wizard account row once a second and opens the port after the mint (MEMORY.md, Live DSL section).
- `flake.nix:786-828` `run-deploy-tests` is the shape of a fresh start: unit env `SASHA_WEB_PORT=8081`, `SASHA_BOOTSTRAP_TOKEN_FILE=/root/bootstrap-token`; wait for `credentials`; `createAccount` with a throwaway key; wait for unit, token file, port; deliver each `.dsl` in sorted order with `deploy-dsl local`; logout; remove the token file.
- `flake.nix:180-201` `deploy-dsl <local|live> <file>`; `live` posts to `https://sashamud.net`; `SASHA_TOKEN` carries the token. `apps.deploy-dsl` and `packages.deploy-dsl` exist (`flake.nix:585, 627`).
- `flake.nix:245-263` `createAccount`: signs the JSON with `SASHA_ACCOUNT_KEY` (default `$HOME/.ssh/sasha_sk`), verifies against `SASHA_ACCOUNT_SIGNERS`, runs `psql "$SASHA_DB_CONNSTR" -f createAccountSql`. `apps.create-account` exists (`flake.nix:632`).
- `flake.nix:264` `wizardAccount`: `{ "player_name": "wizard", "authentik_user_id": "1d2c91c8-fd3d-5ba7-9e29-c2ed7ce38d1d", "role": "wizard" }`.
- World files: `sashamud-world/src/1/World/` then `sashamud-world/src/2/Lobby/1-lobby.dsl`, `2-floor.dsl`, `3-ball.dsl` (MEMORY.md).
- `web/apps/sasha-web/src/game/ViewportManager.ts:65` fetches `http://localhost:${VITE_SLM_PORT}`; `flake.nix:606` bakes `VITE_SLM_PORT=8082`.

deploys:
- `flake.nix:13` `sasha.url = "gitlab:liftlatch/sashamud"`, no ref; pinned by flake.lock.
- `flake.nix:40-76` nixinate: host arges, sshUser mlitchard, port 2222, buildOn local. `nix run .#arges switch`.
- `services/sashamud.nix:1-33` one unit: `SASHA_WEB_PORT=8081`, `SASHA_DB_CONNSTR="dbname=sashamud user=sashamud host=/run/postgresql"`, the two OIDC vars, `ExecStart` = `appPackages.sasha.sasha-server`, `DynamicUser`, `StateDirectory = "sashamud"`, `WorkingDirectory = "/var/lib/sashamud"`. `services.postgresql.ensureDatabases = [ "sashamud" ]`, `ensureUsers` with ownership.
- `systems/arges/default.nix:72` the OIDC secret reaches the unit as a secrix `EnvironmentFile`.
- `flake.nix:94-133` `checks.integration` waits for `sashamud.service` and port 8081.
- `systems/arges/ssh.nix` `AllowTcpForwarding = false`.
- `docs/unedited/2026-10-18-130328-…txt:77-104` the wipe commands, quoted in step 3 below.

## Decisions

1. Wizard account on arges. RULED (user, 2026-10-18): one allowed signer, the admin sk key; no allowed-signers file and no throwaway key on arges. Initial startup is the deploys repo's job: a script in deploys runs over the same YubiKey-gated ssh path as `nix run .#arges`. On arges it creates the wizard row with `psql` and `createAccountSql` over the postgres socket (the `start-sashamud` shape, sashamud `flake.nix:431-436`), waits for the token file, delivers each world `.dsl` from `appPackages.sasha` with `deploy-dsl local` and that token, logs out, removes the token file. Live delivery by players is sashamud's `deploy-dsl` with a login token as a parameter.
2. The `authentik_user_id` for the wizard row on arges. RULED (user, 2026-10-18): the value from `wizardAccount`, `1d2c91c8-fd3d-5ba7-9e29-c2ed7ce38d1d`.
3. DSL delivery at initial startup. RULED (user, 2026-10-18): the deploys initial-startup script delivers on arges with `deploy-dsl local` and the bootstrap token (step 5). Live delivery afterwards is a player's own `deploy-dsl live <file> <token>`.
4. The `sasha` input. RULED (user, 2026-10-18): the input names the branch for now, `sasha.url = "gitlab:liftlatch/sashamud/deploy-slm-changes"`, then `nix flake update sasha`. The merge to main happens after the deploy succeeds.
5. `checks.integration` in deploys. RULED (user, 2026-10-18): the check gains the wizard-row step before `wait_for_open_port(8081)`: wait for `credentials`, then the same `psql` with `createAccountSql` the initial-startup script uses (step 5 item 2).

## Steps

Step rule: every step lands green on its own. A fix a step needs lands in that step.

### Step 0 — sashamud: deploy-dsl takes the token as a parameter (Opus)

RULED (user, 2026-10-18). `flake.nix:180-201` `deployDsl` usage becomes `nix run .#deploy-dsl -- <local|live> <file.dsl> <token>`; `TOKEN="$3"`; the `SASHA_TOKEN` read goes away. Callers in the same step: `start-sashamud` (`flake.nix:441`) passes `"$SASHA_TOKEN"` as the third argument; `run-deploy-tests` (`flake.nix:822-824`) passes `{token}` as the third argument on all three lines and drops the `SASHA_TOKEN={token}` prefix.

Green: `nix flake check` on sashamud.

Addendum, RULED (user, 2026-10-18): `packages` gains `create-account-sql = createAccountSql;` after `deploy-dsl = deployDsl;` (`flake.nix:585`), so deploys reaches the SQL as `appPackages.sasha.create-account-sql`. The world files are `${inputs.sasha}/sashamud-world/src`.

### Step 1 — deploys: bootstrap token file in the unit (deploys-04)

`services/sashamud.nix`, in `environment` after `SASHA_OIDC_REDIRECT_URI`:

```nix
SASHA_BOOTSTRAP_TOKEN_FILE = "/var/lib/sashamud/bootstrap-token";
```

`SASHA_BOOTSTRAP_WIZARD` comes from the wrapper default. Same step, per decision 5: `checks.integration` in `flake.nix` gains the wizard account step before `wait_for_open_port(8081)`.

Green: `nix flake check` in deploys.

### Step 2 — deploys: sasha input (deploys-04)

Per decision 4: `flake.nix:13` becomes `sasha.url = "gitlab:liftlatch/sashamud/deploy-slm-changes";`, then `nix flake update sasha`. Green: `nix build .#checks.x86_64-linux.arges-build` in deploys. You commit.

### Step 3 — arges: fresh database (you)

From `docs/unedited/2026-10-18-130328-…txt:77-104`:

```
ssh -p 2222 mlitchard@arges
sudo systemctl stop sashamud
sudo -u postgres psql -c 'DROP DATABASE sashamud;'
sudo -u postgres psql -c 'CREATE DATABASE sashamud OWNER sashamud;'
```

### Step 4 — deploy (you)

In deploys: `nix run .#arges switch`. On arges: `sudo systemctl start sashamud`. The server runs the migrations, then waits for the wizard row.

### Step 5 — deploys: the initial-startup script (deploys-04), per decision 1

A script in the deploys repo, run from your machine over the same ssh path as `nix run .#arges` (port 2222, user mlitchard, YubiKey). On arges, in order:

1. Wait for the schema: `sudo -u postgres psql sashamud -c 'select 1 from credentials'` succeeds.
2. Create the wizard row: `sudo -u postgres psql sashamud -v ON_ERROR_STOP=1 -v name=wizard -v authentik_user_id=<decision 2> -v role=wizard -f <createAccountSql>`, the `start-sashamud` shape (sashamud `flake.nix:431-436`).
3. Wait for `/var/lib/sashamud/bootstrap-token` and port 8081.
4. For each `.dsl` under `${appPackages.sasha world dir}` in sorted order: `deploy-dsl local <file> <token>` with `deploy-dsl` from `appPackages.sasha`.
5. `curl --fail-with-body -sS -X DELETE http://127.0.0.1:8081/api/game/logout -H "BEARER: <token>"`.
6. Remove the token file.

The SQL is `appPackages.sasha.create-account-sql` (step 0 addendum). The world directory is `${inputs.sasha}/sashamud-world/src`. `deploy-dsl` is `appPackages.sasha.deploy-dsl`.

Green: the script runs to "logout" on arges after step 4.

### Step 6 — you run the initial-startup script

From deploys, after step 4. The world is live when it finishes.

### Step 7 — you inspect

Open `https://sashamud.net`, log in, look around. On a parse failure the browser calls `localhost:8082`; with no local llama-server the failure message arrives as `slm-absent`.
