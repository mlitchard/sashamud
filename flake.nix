{
  description = "SashaMUD monorepo";

  nixConfig = {
    extra-substituters = "https://horizon.cachix.org";
    extra-trusted-public-keys = "horizon.cachix.org-1:MeEEDRhRZTgv/FFGCv3479/dmJDfJ82G6kfUDxMSAw0=";
  };

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";

    horizon-platform.url = "git+https://gitlab.horizon-haskell.net/package-sets/horizon-platform?ref=lts/ghc-9.6.x";

    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    lint-utils = {
      url = "github:homotopic/lint-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    horizon-devtools.url = "git+https://gitlab.horizon-haskell.net/package-sets/horizon-devtools?ref=lts/ghc-9.6.x";

    shelpers.url = "gitlab:platonic/shelpers";

    aeson-generics-typescript = {
      url = "gitlab:platonic/aeson-generics-typescript";
      flake = false;
    };

    servant-aeson-generics-typescript = {
      url = "gitlab:platonic/servant-aeson-generics-typescript";
      flake = false;
    };

    servant-websockets = {
      url = "github:ursi/servant-websockets/TypedWebSocket";
      flake = false;
    };

    local-postgres = {
      url = "github:quelklef/local-postgres";
      flake = false;
    };

    deploys = {
      url = "git+https://gitlab.com/nix-infrastructure/deploys.git";
    };

    authentik-nix.url = "github:nix-community/authentik-nix";
  };

  outputs =
    inputs@{ lint-utils, nixpkgs, ... }:
      with builtins;
      inputs.flake-utils.lib.eachSystem [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ]
        (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;
          hlib = pkgs.haskell.lib;

          rhineSrc = pkgs.fetchFromGitHub {
            owner = "turion";
            repo = "rhine";
            rev = "a4bfa8772602c3434ad191959db615457b91cab5";
            sha256 = "sha256-p0mUfvMmSbsQz4jlZeau7S4FkgtPUv+U9SaChB6Okak=";
          };

          cleanPkgSrc = name:
            let dir = ./. + "/${name}";
            in pkgs.lib.cleanSourceWith {
              src = dir;
              filter = path: type:
                let baseName = baseNameOf path;
                in pkgs.lib.hasSuffix ".hs" baseName
                || pkgs.lib.hasSuffix ".cabal" baseName
                || type == "directory";
            };

          myOverlay = final: _prev: {
            sasha-grammar = final.callCabal2nix "sasha-grammar" (cleanPkgSrc "sasha-grammar") { };
            sasha = final.callCabal2nix "sasha" (cleanPkgSrc "sasha") { };
            sashamud-world = final.callCabal2nix "sashamud-world" (cleanPkgSrc "sashamud-world") { };
            sashamud-server = final.callCabal2nix "sashamud-server" (cleanPkgSrc "sashamud-server") { };
            # Rhine and dependencies
            rhine = hlib.dontCheck (final.callCabal2nix "rhine" "${rhineSrc}/rhine" { });
            automaton = hlib.dontCheck (final.callCabal2nix "automaton" "${rhineSrc}/automaton" { });
            monad-schedule = hlib.dontCheck (final.callCabal2nix "monad-schedule" "${rhineSrc}/monad-schedule" { });
            time-domain = hlib.dontCheck (final.callCabal2nix "time-domain" "${rhineSrc}/time-domain" { });
            changeset =
              let
                changesetSrc = pkgs.fetchFromGitHub {
                  owner = "turion";
                  repo = "changeset";
                  rev = "v0.1.1";
                  sha256 = "sha256-u0nnibT3iAMhRQrBnioooIyBLlV21Z/9fVvDgt+zUQ8=";
                };
              in
              final.callCabal2nix "changeset" "${changesetSrc}/changeset" { };
            simple-affine-space = hlib.dontCheck (final.callHackage "simple-affine-space" "0.2.1" { });
            selective = final.callHackage "selective" "0.7.0.1" { };
            foldable1-classes-compat = final.callHackage "foldable1-classes-compat" "0.1" { };
            monoid-extras =
              let
                src = builtins.fetchTarball {
                  url = "https://hackage.haskell.org/package/monoid-extras-0.7/monoid-extras-0.7.tar.gz";
                  sha256 = "sha256-jXHK6wn8Diel1YPs6hssIRxYU7ceQ9UUdcPjlxj5R7Y=";
                };
              in
              final.callCabal2nix "monoid-extras" src { };
            Earley = final.callHackage "Earley" "0.13.0.1" { };
            # TypeScript codegen
            aeson-typescript = hlib.dontCheck (hlib.doJailbreak
              (final.callCabal2nix "aeson-typescript"
                inputs.aeson-generics-typescript
                { }));
            servant-aeson-typescript = hlib.setBuildTarget
              (hlib.doJailbreak
                (final.callCabal2nix "servant-aeson-typescript"
                  inputs.servant-aeson-generics-typescript
                  { }))
              "lib:servant-aeson-typescript";
            webdriver = final.callHackage "webdriver" "0.12.0.1" { };
            servant-websockets = hlib.dontCheck
              (final.callCabal2nix "servant-websockets"
                inputs.servant-websockets
                { });
          };

          legacyPackages =
            inputs.horizon-platform.legacyPackages.${system}.extend myOverlay;

          hintGhc = legacyPackages.ghcWithPackages (p: [ p.sasha p.sasha-grammar ]);
          hintAttrs = rec {
            HINT_GHC_LIB_DIR = "${hintGhc}/lib/${hintGhc.meta.name}/lib";
            HINT_GHC_PACKAGE_PATH = "${HINT_GHC_LIB_DIR}/package.conf.d";
          };

          dbConnStr = "dbname=sashamud";
          localPostgres = import inputs.local-postgres { inherit pkgs; };
          pgDir = ".database";
          migrationsDir = ./migrations;
          oidcBaseUrl = "http://127.0.0.1:9000";
          oidcClientId = "sashamud";
          oidcClientSecret = "sashamud-dev";
          oidcRedirectUri = "http://localhost:8081/api/auth/callback";

          dslServerUrl = "http://127.0.0.1:8081";
          deployDsl = pkgs.writeShellScript "deploy-dsl" ''
            set -euo pipefail
            SRC="''${1:?usage: nix run .#deploy-dsl -- <file.dsl>}"
            URL="''${SASHA_URL:-${dslServerUrl}}"
            TOKEN="''${SASHA_TOKEN:?SASHA_TOKEN must hold a login token}"
            CURL="${pkgs.curl}/bin/curl"
            JQ="${pkgs.jq}/bin/jq"
            $JQ -Rs . < "$SRC" | $CURL --fail-with-body -sS -X POST "$URL/api/game/dsl" \
              -H "Sec-WebSocket-Protocol: $TOKEN" -H "Content-Type: application/json" \
              --data @-
            echo "deployed $SRC to $URL"
          '';
          fakeLogin = pkgs.writeShellScript "fake-login" ''
            set -euo pipefail
            URL="''${1:-${dslServerUrl}}"
            USER="''${2:-wizard}"
            CURL="${pkgs.curl}/bin/curl"
            location() {
              $CURL -sS -o /dev/null -D - "$1" | tr -d '\r' | ${pkgs.gawk}/bin/awk 'tolower($1) == "location:" { print $2 }'
            }
            AUTHORIZE=$(location "$URL/api/auth/start")
            CALLBACK=$(location "$AUTHORIZE&fake_user=$USER")
            FINAL=$(location "$CALLBACK")
            echo "$FINAL" | ${pkgs.gnused}/bin/sed 's|^/#token=||'
          '';
          accountSigningKey = "\${HOME}/.ssh/sasha_sk";
          accountSigners = pkgs.writeText "sashamud-allowed-signers" ''
            sashamud-admin sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIGIQxWd6UuR8QMyqLQxTjSjrfrdOEAIcw7ilskEW5JDlAAAABHNzaDo=
          '';
          createAccountSql = pkgs.writeText "create-account.sql" ''
            WITH new_user AS (
              INSERT INTO users (status, role_id, activated_on)
                SELECT 'active', role_id, now() FROM roles
                  WHERE name = :'role'
                    AND NOT EXISTS (SELECT 1 FROM credentials WHERE player_name = :'name')
                RETURNING user_id)
            INSERT INTO credentials (user_id, player_name, authentik_user_id)
              SELECT user_id, :'name', :'authentik_user_id' FROM new_user
              ON CONFLICT (player_name) DO NOTHING;
          '';
          createAccount = pkgs.writeShellScript "create-account" ''
            set -euo pipefail
            ACCOUNT="''${1:?usage: nix run .#create-account -- <account.json>}"
            KEY="''${SASHA_ACCOUNT_KEY:-${accountSigningKey}}"
            SIGNERS="''${SASHA_ACCOUNT_SIGNERS:-${accountSigners}}"
            CONNSTR="''${SASHA_DB_CONNSTR:-${dbConnStr}}"
            JQ="${pkgs.jq}/bin/jq"
            KEYGEN="${pkgs.openssh}/bin/ssh-keygen"
            PSQL="${pkgs.postgresql}/bin/psql"
            NAME=$($JQ -r .player_name "$ACCOUNT")
            AUTHENTIK_USER_ID=$($JQ -r .authentik_user_id "$ACCOUNT")
            ROLE=$($JQ -r .role "$ACCOUNT")
            SIG=$(${pkgs.coreutils}/bin/mktemp)
            trap 'rm -f "$SIG"' EXIT
            $KEYGEN -Y sign -f "$KEY" -n sashamud-account < "$ACCOUNT" > "$SIG"
            $KEYGEN -Y verify -f "$SIGNERS" -I sashamud-admin -n sashamud-account -s "$SIG" < "$ACCOUNT"
            $PSQL "$CONNSTR" -v ON_ERROR_STOP=1 -v name="$NAME" -v authentik_user_id="$AUTHENTIK_USER_ID" -v role="$ROLE" -f ${createAccountSql}
            echo "account $NAME ($ROLE) is present"
          '';
          wizardAccount = pkgs.writeText "wizard-account.json" ''
            { "player_name": "wizard", "authentik_user_id": "1d2c91c8-fd3d-5ba7-9e29-c2ed7ce38d1d", "role": "wizard" }
          '';

          devtools = inputs.horizon-devtools.packages.${system};
          lu = lint-utils.linters.${system};
          lu-pkgs = lint-utils.packages.${system};
          projectRoot = ./.;

          webNpmDeps = pkgs.fetchNpmDeps {
            src = lib.fileset.toSource {
              root = ./web;
              fileset = lib.fileset.fileFilter (f: f.hasExt "json") ./web;
            };
            hash = "sha256-yexn2zbub03CT9aIgkd3XwySAfO7jW4vbvl6QOkU+SQ=";
          };

          teardown = script: teardown': ''
            (set -e
            ${script}
            trap ${lib.escapeShellArg teardown'} SIGINT
            wait)
          '';

          shelpersConfig = (inputs.shelpers.lib pkgs).eval-shelpers [
            ({ shelp, ... }: {
              instructions-order = [ "Info" "Validate" "Database" "Run" ];
              shelpers."." = {
                "Info" = {
                  inherit shelp;
                };
                "Validate" = {
                  check = {
                    description = "run nix flake check with logs";
                    script = "nix flake check -L";
                  };
                  fmt-cabal = {
                    description = "format all .cabal files in the repo";
                    script = ''
                      ${lib.getExe lu-pkgs.cabal-fmt} -i **/*.cabal
                    '';
                  };
                  fmt-haskell = {
                    description = "apply stylish-haskell to all .hs files in the repo";
                    script = ''
                      find sasha-grammar sasha sashamud-world sashamud-server -name '*.hs' -exec ${lib.getExe lu-pkgs.stylish-haskell} -i {} +
                    '';
                  };
                  lint-ts = {
                    description = "lint all TypeScript files";
                    script = ''
                      cd web && npm run lint
                    '';
                  };
                  fmt-ts = {
                    description = "lint and fix all TypeScript files";
                    script = ''
                      cd web && npm run lint-fix
                    '';
                  };
                  typecheck-ts = {
                    description = "typecheck the TypeScript frontend";
                    script = ''
                      cd web && npm run typecheck
                    '';
                  };
                };
                "Database" = {
                  create-db = {
                    description = "create the local database cluster";
                    internal = true;
                    script = ''
                      if [[ -e ${pgDir} ]]; then
                        echo database has already been created
                      else
                        lpg make ${pgDir}
                      fi
                    '';
                  };
                  db-server-start = {
                    description = "start the database server";
                    script = ''
                      if [[ -e ${pgDir} ]]; then
                        lpg on ${pgDir} up
                        export SASHA_DB_CONNSTR=$(lpg on ${pgDir} get-connstr)
                      else
                        echo 'No database exists, run `reset-db` and try again.'
                      fi
                    '';
                  };
                  db-server-stop = {
                    description = "stop the database server";
                    script = ''
                      lpg on ${pgDir} down || true
                      unset SASHA_DB_CONNSTR
                    '';
                  };
                  db-shell = {
                    description = "enter a psql shell for the local database";
                    script = ''
                      if [[ -e ${pgDir} ]]; then
                        db-server-start
                        lpg on ${pgDir} psql
                      else
                        echo 'No database exists, run `reset-db` and try again.'
                      fi
                    '';
                  };
                  reset-db = {
                    description = "destroy (if it exists) and then recreate the local database";
                    script = ''
                      destroy-db
                      create-db
                    '';
                  };
                  destroy-db = {
                    description = "destroy the local database";
                    script = ''
                      db-server-stop
                      rm ${pgDir} -r || true
                    '';
                  };
                };
                "Run" = {
                  hint-env = {
                    description = "export HINT_GHC_LIB_DIR and HINT_GHC_PACKAGE_PATH into this shell";
                    script = ''
                      HINT_GHC=$(nix build --no-link --print-out-paths .#hint-ghc)
                      export HINT_GHC_LIB_DIR="$HINT_GHC/lib/$(nix eval --raw .#hint-ghc.meta.name)/lib"
                      export HINT_GHC_PACKAGE_PATH="$HINT_GHC_LIB_DIR/package.conf.d"
                    '';
                  };
                  start-sashamud = {
                    description = "generate TS client, build frontend, start full stack";
                    script = teardown
                      ''
                        (cd web && npm install && npm run build)
                        caddy run --config Caddyfile &
                        nix run .#sasha-server &
                      ''
                      ''
                        kill $(jobs -p) 2>/dev/null
                      '';
                  };
                };
              };
            })
          ];
        in
        {
          inherit legacyPackages;
          shelpers = shelpersConfig.files;

          devShells.default = (legacyPackages.shellFor {
            packages = p: [
              p.sasha-grammar
              p.sasha
              p.sashamud-world
              p.sashamud-server
            ];
          }).overrideAttrs (attrs: {
            buildInputs = attrs.buildInputs ++ [
              pkgs.cabal-install
              lu-pkgs.cabal-fmt
              lu-pkgs.hlint
              lu-pkgs.stylish-haskell
              pkgs.caddy
              pkgs.nodejs
              pkgs.typescript
              pkgs.postgresql
              localPostgres
            ] ++ lib.optionals (system == "x86_64-linux") [
              devtools.haskell-language-server
            ];
            shellHook = ''
              export SASHA_MIGRATIONS_DIR=${migrationsDir}
              export SASHA_OIDC_REDIRECT_URI=https://localhost:8080/api/auth/callback
              ${shelpersConfig.functions}
              shelp
            '';
          });

          packages = {
            hint-ghc = hintGhc;
            sasha-server = (hlib.overrideCabal
              (hlib.justStaticExecutables
                (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sashamud-server "exe:sasha-server")))
              (drv: { disallowGhcReference = false; })).overrideAttrs (old: {
              meta.mainProgram = "sasha-server";
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
              postFixup = (old.postFixup or "") + ''
                wrapProgram $out/bin/sasha-server \
                  --set-default HINT_GHC_LIB_DIR ${hintAttrs.HINT_GHC_LIB_DIR} \
                  --set-default HINT_GHC_PACKAGE_PATH ${hintAttrs.HINT_GHC_PACKAGE_PATH} \
                  --set-default SASHA_DB_CONNSTR ${dbConnStr} \
                  --set-default SASHA_MIGRATIONS_DIR ${migrationsDir} \
                  --set-default SASHA_OIDC_BASE_URL ${oidcBaseUrl} \
                  --set-default SASHA_OIDC_CLIENT_ID ${oidcClientId} \
                  --set-default SASHA_OIDC_CLIENT_SECRET ${oidcClientSecret} \
                  --set-default SASHA_OIDC_REDIRECT_URI ${oidcRedirectUri}
              '';
            });
            sasha-client-generator = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sasha "exe:sasha-client-generator"))).overrideAttrs { meta.mainProgram = "sasha-client-generator"; };
            sasha-tests = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sasha "exe:sasha-tests"))).overrideAttrs { meta.mainProgram = "sasha-tests"; };
            sasha-fake-oidc = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sashamud-server "exe:sasha-fake-oidc"))).overrideAttrs { meta.mainProgram = "sasha-fake-oidc"; };
            grammar-tests = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sasha-grammar "exe:grammar-tests"))).overrideAttrs { meta.mainProgram = "grammar-tests"; };
            sasha-e2e-tests = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sashamud-server "exe:sasha-e2e-tests"))).overrideAttrs { meta.mainProgram = "sasha-e2e-tests"; };
            web =
              let
                generated-ts-path = "packages/type-gen-output/src/client.ts";
                client-ts = pkgs.runCommand "client.ts" { }
                  "${legacyPackages.sasha}/bin/sasha-client-generator $out";
                npmBuild = pkgs.buildNpmPackage {
                  name = "npm-build-sasha-web";
                  src = pkgs.runCommand "npm-src" { } ''
                    mkdir $out; cd $_
                    cp -r ${./web}/. .
                    chmod -R +w .
                    mkdir -p $(dirname ${generated-ts-path})
                    ln -sf ${client-ts} ${generated-ts-path}
                  '';
                  npmDeps = webNpmDeps;
                  dontNpmBuild = true;
                  buildPhase = ''
                    cd apps/sasha-web
                    node node_modules/vite/bin/vite.js build
                    cd ../..
                  '';
                  installPhase = ''
                    mkdir -p $out
                    cp -r apps/sasha-web/dist/* $out/
                  '';
                };
              in
              npmBuild;
          };

          formatter = pkgs.nixpkgs-fmt;

          apps.fmt = {
            type = "app";
            program = toString (pkgs.writeShellScript "fmt" ''
              find "''${1:-.}" -name '*.nix' -not -path '*/node_modules/*' -exec ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt {} +
            '');
          };

          apps.deploy-dsl = {
            type = "app";
            program = toString deployDsl;
          };

          apps.create-account = {
            type = "app";
            program = toString createAccount;
          };

          apps.authentik-vm = {
            type = "app";
            program = "${inputs.self.nixosConfigurations.authentik-local.config.system.build.vm}/bin/run-authentik-local-vm";
          };

          checks = {
            nix-formatting = pkgs.runCommand "nix-formatting" { buildInputs = [ pkgs.nixpkgs-fmt ]; } ''
              nixpkgs-fmt --check ${./flake.nix}
              echo 0 > $out
            '';
            cabal-formatting = lu.cabal-fmt {
              src = pkgs.lib.cleanSourceWith {
                src = projectRoot;
                filter = path: type:
                  let
                    baseName = baseNameOf path;
                    excluded = baseName == "attic" || baseName == "dist-newstyle" || baseName == ".git" || baseName == "result";
                  in
                  !excluded && (
                    lib.hasSuffix ".cabal" baseName
                    || type == "directory"
                  );
              };
            };
            haskell-formatting = (lu.stylish-haskell {
              src = pkgs.lib.cleanSourceWith {
                src = projectRoot;
                filter = path: type:
                  let
                    baseName = baseNameOf path;
                    excluded = baseName == "attic" || baseName == "dist-newstyle" || baseName == ".git" || baseName == "result";
                  in
                  !excluded && (
                    lib.hasSuffix ".hs" baseName
                    || lib.hasSuffix ".cabal" baseName
                    || baseName == ".stylish-haskell.yaml"
                    || type == "directory"
                  );
              };
            }).overrideAttrs (old: { LANG = "C.UTF-8"; LC_ALL = "C.UTF-8"; });
            haskell-linting = (lu.hlint {
              src = pkgs.lib.cleanSourceWith {
                src = projectRoot;
                filter = path: type:
                  let
                    baseName = baseNameOf path;
                    excluded = baseName == "attic" || baseName == "dist-newstyle" || baseName == ".git" || baseName == "result";
                  in
                  !excluded && (
                    lib.hasSuffix ".hs" baseName
                    || baseName == ".hlint.yaml"
                    || type == "directory"
                  );
              };
            }).overrideAttrs (old: { LANG = "C.UTF-8"; LC_ALL = "C.UTF-8"; });
            ts-linting = pkgs.buildNpmPackage {
              name = "ts-linting";
              src = ./web;
              npmDeps = webNpmDeps;
              dontNpmBuild = true;
              buildPhase = ''
                node_modules/.bin/eslint .
              '';
              installPhase = ''
                echo 0 > $out
              '';
            };
            ts-typecheck = pkgs.buildNpmPackage {
              name = "ts-typecheck";
              src = ./web;
              npmDeps = webNpmDeps;
              dontNpmBuild = true;
              nativeBuildInputs = [ legacyPackages.sasha ];
              buildPhase = ''
                sasha-client-generator packages/type-gen-output/src/client.ts
                node_modules/.bin/tsc -p apps/sasha-web/tsconfig.json --noEmit
              '';
              installPhase = ''
                echo 0 > $out
              '';
            };
            haskell-warnings-sasha = lu.werror { pkg = legacyPackages.sasha; };
            haskell-warnings-grammar = lu.werror { pkg = legacyPackages.sasha-grammar; };
            haskell-warnings-world = lu.werror { pkg = legacyPackages.sashamud-world; };
            haskell-warnings-server = lu.werror { pkg = legacyPackages.sashamud-server; };
            client-check =
              let
                client-ts = pkgs.runCommand "client.ts" { }
                  "${legacyPackages.sasha}/bin/sasha-client-generator $out";
              in
              pkgs.runCommand "client-check" { buildInputs = [ pkgs.typescript ]; } ''
                tsc --lib "ES2021","DOM" ${client-ts} --noEmit --strict
                echo 0 > $out
              '';
            run-grammar-tests = pkgs.testers.runNixOSTest {
              name = "grammar-tests";
              nodes.machine = { pkgs, ... }: {
                environment.systemPackages = [
                  inputs.self.packages.${system}.grammar-tests
                ];
                virtualisation = {
                  memorySize = 32768;
                  cores = 2;
                };
              };
              testScript = ''
                machine.wait_for_unit("default.target")
                print(machine.succeed("grammar-tests"))
              '';
            };
            run-sasha-tests = pkgs.testers.runNixOSTest {
              name = "sasha-tests";
              nodes.machine = { pkgs, ... }: {
                services.postgresql = {
                  enable = true;
                  ensureDatabases = [ "sashamud" ];
                  ensureUsers = [{ name = "root"; ensureClauses.superuser = true; }];
                  package = pkgs.postgresql;
                };
                environment.systemPackages = [
                  inputs.self.packages.${system}.sasha-tests
                ];
                environment.variables = hintAttrs // {
                  SASHA_DB_CONNSTR = dbConnStr;
                  SASHA_MIGRATIONS_DIR = "${migrationsDir}";
                };
                virtualisation = {
                  memorySize = 32768;
                  cores = 2;
                };
              };
              testScript = ''
                machine.wait_for_unit("default.target")
                print(machine.succeed("sasha-tests"))
              '';
            };
            run-deploy-tests = pkgs.testers.runNixOSTest {
              name = "deploy-tests";
              nodes.machine = { pkgs, ... }: {
                services.postgresql = {
                  enable = true;
                  ensureDatabases = [ "sashamud" ];
                  ensureUsers = [{ name = "root"; ensureClauses.superuser = true; }];
                  package = pkgs.postgresql;
                };
                systemd.services.sashamud = {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" "postgresql.service" ];
                  requires = [ "postgresql.service" ];
                  environment.SASHA_WEB_PORT = "8081";
                  serviceConfig = {
                    ExecStart = lib.getExe inputs.self.packages.${system}.sasha-server;
                    Restart = "on-failure";
                  };
                };
                systemd.services.sasha-fake-oidc = {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "network.target" ];
                  serviceConfig = {
                    ExecStart = lib.getExe inputs.self.packages.${system}.sasha-fake-oidc;
                    Restart = "on-failure";
                  };
                };
                virtualisation = {
                  memorySize = 32768;
                  cores = 2;
                };
              };
              testScript = ''
                machine.wait_for_unit("sashamud.service")
                machine.wait_for_open_port(8081)
                machine.wait_for_unit("sasha-fake-oidc.service")
                machine.wait_for_open_port(9000)
                machine.succeed('${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f /root/account-key')
                machine.succeed('echo "sashamud-admin $(cut -d" " -f1,2 /root/account-key.pub)" > /root/account-signers')
                machine.succeed("SASHA_ACCOUNT_KEY=/root/account-key SASHA_ACCOUNT_SIGNERS=/root/account-signers ${createAccount} ${wizardAccount}")
                token = machine.succeed("${fakeLogin} ${dslServerUrl} wizard").strip()
                print(machine.succeed(f"SASHA_TOKEN={token} ${deployDsl} ${./sashamud-server/test-e2e/study.dsl}"))
              '';
            };
            run-end-to-end =
              let
                sasha-e2e-wrapped = pkgs.writeShellScriptBin "sasha-e2e-wrapped" ''
                  set -ex

                  echo "Starting Selenium server..."
                  selenium-server > selenium.log 2>&1 &
                  PID=$!

                  MAX_RETRIES=120
                  RETRY_COUNT=0

                  until
                    curl_output=$(curl -s http://localhost:4444/wd/hub/status)
                    echo "$curl_output" | grep -q '"ready": true'
                  do
                    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
                      echo "Selenium server failed to become ready after $MAX_RETRIES attempts."
                      kill $PID
                      exit 1
                    fi
                    echo "Waiting for Selenium server... Attempt $((RETRY_COUNT+1))/$MAX_RETRIES"
                    sleep 1
                    RETRY_COUNT=$((RETRY_COUNT+1))
                  done

                  echo "Selenium server is ready."
                  echo "Running sasha end-to-end tests..."

                  ${lib.getExe inputs.self.packages.${system}.sasha-e2e-tests} || {
                    echo "Tests failed with exit code $?"
                    kill $PID
                    exit 1
                  }

                  echo "Tests completed. Shutting down Selenium server..."
                  kill $PID
                  exit 0
                '';
              in
              pkgs.testers.runNixOSTest {
                name = "sasha-end-to-end";
                nodes.machine = { pkgs, ... }: {
                  imports = [
                    inputs.deploys.nixosModules.caddy-proxy-host
                  ];
                  services.caddyProxyHost."localhost:4430" = {
                    routes = [
                      { match = "/ws/*"; upstream = "localhost:8081"; }
                      { match = "/api/*"; upstream = "localhost:8081"; }
                    ];
                  };
                  services.postgresql = {
                    enable = true;
                    ensureDatabases = [ "sashamud" ];
                    ensureUsers = [{ name = "root"; ensureClauses.superuser = true; }];
                    package = pkgs.postgresql;
                  };
                  systemd.services.sashamud = {
                    wantedBy = [ "multi-user.target" ];
                    after = [ "network.target" "caddy.service" "postgresql.service" ];
                    requires = [ "postgresql.service" ];
                    environment.SASHA_WEB_PORT = "8081";
                    serviceConfig = {
                      ExecStart = lib.getExe inputs.self.packages.${system}.sasha-server;
                      Restart = "on-failure";
                    };
                  };
                  environment.variables = {
                    SASHA_DB_CONNSTR = dbConnStr;
                    SASHA_MIGRATIONS_DIR = "${migrationsDir}";
                  };
                  environment.systemPackages = [
                    sasha-e2e-wrapped
                    pkgs.selenium-server-standalone
                    pkgs.chromedriver
                    pkgs.chromium
                    pkgs.nodejs
                    pkgs.typescript
                  ];
                  virtualisation = {
                    memorySize = 32768;
                    cores = 2;
                  };
                };
                testScript = ''
                  machine.wait_for_unit("caddy.service")
                  machine.wait_for_unit("sashamud.service")
                  machine.wait_for_open_port(8081)
                  machine.wait_for_open_port(4430)
                  print(machine.succeed("${lib.getExe sasha-e2e-wrapped}"))
                '';
              };
            run-integration-tests = legacyPackages.sashamud-server.overrideAttrs (old: {
              doCheck = true;
            });
          };
        }) // {
        nixosConfigurations.authentik-local = inputs.authentik-nix.inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.authentik-nix.nixosModules.default
            {
              networking.hostName = "authentik-local";
              system.stateVersion = "25.05";
              fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };
              boot.loader.grub.devices = [ "/dev/vda" ];
              services.authentik = {
                enable = true;
                environmentFile = "/etc/authentik.env";
              };
              systemd.tmpfiles.rules = [
                "f /etc/authentik.env 0700 root root - AUTHENTIK_SECRET_KEY=sashamud-local-authentik-secret-key"
              ];
              environment.variables = {
                SASHA_OIDC_BASE_URL = "http://localhost:9000";
                SASHA_OIDC_CLIENT_ID = "sashamud";
                SASHA_OIDC_CLIENT_SECRET = "sashamud-dev";
                SASHA_OIDC_REDIRECT_URI = "https://localhost:8080/api/auth/callback";
              };
              virtualisation.vmVariant.virtualisation = {
                memorySize = 3072;
                cores = 3;
                forwardPorts = [{ from = "host"; host.port = 9000; guest.port = 9000; }];
              };
            }
          ];
        };
      };
}
