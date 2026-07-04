{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    limmat.url = "github:bjackman/limmat";
    flake-utils.url = "github:numtide/flake-utils";
    kernel = {
      url = "github:torvalds/linux";
      flake = false;
    };
    blktests = {
      url = "github:linux-blktests/blktests";
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
    let
      overlaysBySystem = {
        ${flake-utils.lib.system.x86_64-linux} = [ ];
        ${flake-utils.lib.system.i686-linux} = [
          # Disable ShellCheck so we don't have to compile GHC.
          (self: super: {
            writeShellApplication =
              args:
              (super.writeShellApplication args).overrideAttrs (old: {
                nativeBuildInputs = self.lib.filter (
                  x: !self.lib.hasInfix "shellcheck" (self.lib.toLower (x.name or ""))
                ) (old.nativeBuildInputs or [ ]);
                checkPhase = ":";
              });
          })
        ];
        ${flake-utils.lib.system.aarch64-linux} = [ ];
      };
    in
    (flake-utils.lib.eachSystem (builtins.attrNames overlaysBySystem) (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = overlaysBySystem.${system};
        };
        limmat = inputs.limmat.packages."${system}".limmat-wrapped;
        limmatConfig = (
          pkgs.callPackage ./limmat-config.nix {
            lk-vm = self.packages."${system}".lk-vm;
            lk-kconfig = self.packages."${system}".lk-kconfig;
            inherit inputs;
          }
        );
        format = pkgs.formats.toml { };
      in
      {
        formatter = pkgs.nixfmt-tree;
        checks = self.packages.${system} // {
          fmt = pkgs.callPackage ./check-nix-fmt.nix { };
        };

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
          blktests = pkgs.callPackage ./blktests.nix {
            inherit inputs;
          };
          # Little tool for running tests.
          test-runner = pkgs.buildGoModule {
            pname = "test-runner";
            version = "0.1.0";
            src = ./test-runner;
            vendorHash = "sha256-BCgQzMak7ebugES9UxNshpiH9VK+er5cxKS2aV6ogso=";
          };
          # Tool plus a config to run some kernel tests.
          ktests = pkgs.callPackage ./ktests.nix {
            inherit blktests kselftests test-runner;
          };
          # Some experimental tools for stress-testing. This is different from
          # ktests in that they run continuously so they never produce a "pass"
          # signal.
          kstresstests = pkgs.callPackage ./kstresstests.nix { };

          lk-vm = pkgs.callPackage ./lk-vm {
            inherit self;
            i686Pkgs = import nixpkgs {
              system = "i686-linux";
              overlays = overlaysBySystem."i686-linux";
            };
          };
          lk-kconfig = pkgs.callPackage ./lk-kconfig.nix { };

          golden-kernel = pkgs.callPackage ./golden-kernel.nix {
            inherit lk-kconfig;
            kernelSrc = kernel;
          };

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
            pkgs.linuxPackages.kernel
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
              # TODO: Add support for LLVM builds. Gemini is too stupid to
              # figure this one out, it keeps going round in reasoning circles
              # and making shit up. I think the key challlenge is that we need
              # to use clang-unwrapped for the target builds, but use the
              # wrapper for host tools. You can kinda work around this by just
              # building with  LLVM=1 HOSTCC=cc HOSTLD=ld.
              # Add clangd - don't yet support actually building with LLVM but
              # clangd is (mostly) compatible with GCC luckily.
              clang-tools
            ])
            ++ (with self.packages."${system}"; [
              lk-vm
              lk-kconfig
            ])
            ++ limmatConfig.runtimeInputs;
          LIMMAT_CONFIG = self.packages."${system}".limmatTOML;
          # Don't care about -march=native for this devShell.
          NIX_ENFORCE_NO_NATIVE = 0;
        };
      }
    ))
    // {
      # Packages intended for use in the lk-vm guest.
      overlays.guest = final: prev: {
        inherit (self.packages.${prev.stdenv.hostPlatform.system})
          ktests
          kselftests
          test-runner
          kstresstests
          ;
      };
    };
}
