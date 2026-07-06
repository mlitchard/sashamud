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
            sasha-vocabulary = final.callCabal2nix "sasha-vocabulary" (cleanPkgSrc "sasha-vocabulary") { };
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
            servant-websockets = hlib.dontCheck
              (final.callCabal2nix "servant-websockets"
                inputs.servant-websockets
                { });
          };

          legacyPackages =
            inputs.horizon-platform.legacyPackages.${system}.extend myOverlay;

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
              instructions-order = [ "Info" "Validate" "Run" ];
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
                      find sasha-grammar sasha-vocabulary sasha sashamud-world sashamud-server -name '*.hs' -exec ${lib.getExe lu-pkgs.stylish-haskell} -i {} +
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
                "Run" = {
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
              p.sasha-vocabulary
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
            ] ++ lib.optionals (system == "x86_64-linux") [
              devtools.haskell-language-server
            ];
            shellHook = ''
              ${shelpersConfig.functions}
              shelp
            '';
          });

          packages = {
            sasha-server = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sashamud-server "exe:sasha-server"))).overrideAttrs { meta.mainProgram = "sasha-server"; };
            sasha-client-generator = (hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sasha "exe:sasha-client-generator"))).overrideAttrs { meta.mainProgram = "sasha-client-generator"; };
            sasha-tests = hlib.justStaticExecutables
              (hlib.dontCheck (hlib.setBuildTarget legacyPackages.sasha "exe:sasha-tests"));
          };

          formatter = pkgs.nixpkgs-fmt;

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
            haskell-warnings-vocabulary = lu.werror { pkg = legacyPackages.sasha-vocabulary; };
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
            run-sasha-tests = pkgs.testers.runNixOSTest {
              name = "sasha-tests";
              nodes.machine = { pkgs, ... }: {
                environment.systemPackages = [
                  inputs.self.packages.${system}.sasha-tests
                ];
              };
              testScript = ''
                machine.wait_for_unit("default.target")
                machine.succeed("sasha-tests")
              '';
            };
            run-integration-tests = legacyPackages.sashamud-server.overrideAttrs (old: {
              doCheck = true;
            });
          };
        });
}
