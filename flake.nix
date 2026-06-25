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

    shelpers.url = "gitlab:platonic/shelpers";
  };

  outputs =
    inputs@{ nixpkgs, ... }:
    inputs.flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
    ]
      (system:
      let
        pkgs = import nixpkgs { inherit system; };

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
        };

        legacyPackages =
          inputs.horizon-platform.legacyPackages.${system}.extend myOverlay;

        shelpersConfig = (inputs.shelpers.lib pkgs).eval-shelpers [
          ({ shelp, ... }: {
            instructions-order = [ "Info" ];
            shelpers."." = {
              "Info" = {
                inherit shelp;
              };
            };
          })
        ];
      in
      {
        inherit legacyPackages;
        shelpers = shelpersConfig.files;

        formatter = pkgs.nixpkgs-fmt;

        checks = {
          nix-formatting = pkgs.runCommand "nix-formatting" { buildInputs = [ pkgs.nixpkgs-fmt ]; } ''
            nixpkgs-fmt --check ${./flake.nix}
            echo 0 > $out
          '';
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.cabal-install
            pkgs.nodejs
            pkgs.typescript
          ];
          shellHook = ''
            ${shelpersConfig.functions}
            shelp
          '';
        };
      });
}
