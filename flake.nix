{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    limmat.url = "github:bjackman/limmat";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        limmat = inputs.limmat.packages."${system}".default;
        # This package will be used for golden testing, and also to grab the
        # toolchains etc for the devShell.
        refKernel = pkgs.linuxPackages.kernel;
        limmatConfig =
          (pkgs.callPackage ./limmat-config.nix {
            kernelDevShell = self.devShells."${system}".kernel;
          }).config;
        format = pkgs.formats.toml { };
      in
      {
        formatter = pkgs.nixfmt-tree;
        checks.default = pkgs.callPackage ./check-nix-fmt.nix { };

        packages = rec {
          limmatTOML = format.generate "limmat.toml" limmatConfig;

          limmat-kernel = pkgs.stdenv.mkDerivation {
            pname = "limmat-kernel";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              makeWrapper ${limmat}/bin/limmat $out/bin/limmat-kernel \
                --set LIMMAT_CONFIG ${limmatTOML}
            '';
          };
          default = limmat-kernel;
        };

        # Because of the hackery involved in this system, where we use `nix
        # develop` from within the config, this can't be tested via a normal
        # flake check which would run inside the build sandbox. So instead the
        # tests for the config are exposed as an app that is run
        # non-hermetically.
        apps = {
          test-golden = flake-utils.lib.mkApp {
            drv = pkgs.callPackage ./test-golden.nix {
              # Passing packages "manually" as a normal arg like this might be
              # in poor taste, I'm not sure. Like maybe the "proper" way is via
              # a nixpkgs overlay or something like that.
              limmat-kernel = self.packages."${system}".limmat-kernel;
              inherit limmatConfig;
              inherit refKernel;
            };
          };

          vm-run = flake-utils.lib.mkApp {
            drv = pkgs.callPackage ./vm-run.nix {
              nixosSystem = nixpkgs.lib.nixosSystem;
            };
          };
        };

        devShells.kernel = pkgs.mkShell {
          inputsFrom = [ refKernel ];
          packages = [ pkgs.ccache ];
        };
      }
    );
}
