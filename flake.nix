{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    limmat.url = "github:bjackman/limmat";
    flake-utils.url = "github:numtide/flake-utils";
    kernel = {
      url = "github:torvalds/linux";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      kernel,
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
        limmatConfig = (
          pkgs.callPackage ./limmat-config.nix {
            lk-vm = self.packages."${system}".lk-vm;
            lk-kconfig = self.packages."${system}".lk-kconfig;
          }
        );
        format = pkgs.formats.toml { };
      in
      {
        formatter = pkgs.nixfmt-tree;
        checks.default = pkgs.callPackage ./check-nix-fmt.nix { };

        packages = rec {
          # Export the TOML as a separate package. Also smush the limmatConfig
          # attrset onto this output package so it's easily accessible via 'nix
          # eval .#limatConfig.config' for debugging.
          limmatTOML = format.generate "limmat.toml" limmatConfig.config // limmatConfig;

          # Mostly for convenient testing, export a version of Limmat with the
          # config from this repo hard-coded into it. Usually you'll instead
          # just want to run the 'limmat' command from a devShell instead.
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

          # Version of kselftests built from the nixpkgs kernel.
          kselftests = pkgs.callPackage ./kselftests.nix {
            kernelSrc = kernel;
          };
          # Little tool for running tests.
          test-runner = pkgs.buildGoModule {
            pname = "test-runner";
            version = "0.1.0";
            src = ./test-runner;
            vendorHash = "sha256-uPqabZgQGQulf+F3BvMLhv4O0h5jOq12F7K60u5xjtA=";
          };
          # Tool plus a config to run some kernel tests.
          ktests = pkgs.callPackage ./ktests.nix {
            inherit kselftests test-runner;
          };

          lk-vm = pkgs.callPackage ./lk-vm.nix {
            nixosSystem = nixpkgs.lib.nixosSystem;
            inherit ktests kselftests;
          };
          lk-kconfig = pkgs.callPackage ./lk-kconfig.nix { };

          # Because of the hackery involved in this system, where we use `nix
          # develop` from within the config, this can't be tested via a normal
          # flake check which would run inside the build sandbox. So instead the
          # tests for the config are exposed as a package that is run
          # non-hermetically.
          test-golden = pkgs.callPackage ./test-golden.nix {
            # Passing packages "manually" as a normal arg like this might be
            # in poor taste, I'm not sure. Like maybe the "proper" way is via
            # a nixpkgs overlay or something like that.
            limmat-kernel = self.packages."${system}".limmat-kernel;
            inherit limmatConfig;
            kernelSrc = kernel;
          };
        };

        devShells.kernel = pkgs.mkShell {
          inputsFrom = [
            refKernel
            self.packages."${system}".kselftests
          ];
          packages =
            (with pkgs; [
              ccache
              ncurses
              gdb
              # This adds a `cc` binary (etc) to $PATH that will cause them to
              # use ccache. There's no other ccache configuration in here so
              # this will just use the user's global configuration/cache etc.
              ccacheWrapper

              # For building the user-mode tests like tools/testing/vma
              liburcu

              limmat
              b4
              codespell
            ])
            ++ (with self.packages."${system}"; [
              lk-vm
              lk-kconfig
            ])
            ++ limmatConfig.runtimeInputs;
          LIMMAT_CONFIG = self.packages."${system}".limmatTOML;
          MY_ENV = "foo";
        };
      }
    );
}
