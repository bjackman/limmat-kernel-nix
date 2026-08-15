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
        # Shellcheck is a Haskell program, 32-bit builds aren't cached, we don't
        # want to compile a Haskell toolchain.
        ${flake-utils.lib.system.i686-linux} = [ self.overlays.noShellcheck ];
        ${flake-utils.lib.system.aarch64-linux} = [ ];
      };
    in
    (flake-utils.lib.eachSystem (builtins.attrNames overlaysBySystem) (
      system:
      let
        # Every nixpkgs instantiation in this flake happens here. Package sets
        # are native for their system, so they substitute from the cache; a
        # guest of another arch gets its OS and most of its test packages from
        # here (see guestCrossPkgs for the exceptions).
        guestPkgs = nixpkgs.lib.genAttrs (builtins.attrNames overlaysBySystem) (
          targetSystem:
          import nixpkgs {
            system = targetSystem;
            overlays = overlaysBySystem.${targetSystem} ++ [ self.overlays.guest ];
          }
        );
        pkgs = guestPkgs.${system};

        # Cross-compiled package sets, keyed by target system. Only for the
        # guest packages built from sources no cache can know about (the kernel
        # input, this repo); cross-compiling those beats emulating them.
        # Everything else must come from guestPkgs: cross-compiling a package
        # means cross-compiling its whole dependency closure, and no cache has
        # cross builds.
        guestCrossPkgs = {
          aarch64-linux = pkgs.pkgsCross.aarch64-multiplatform.extend (
            final: prev: {
              # Cross-compile the selftests themselves, but take their
              # dependencies from the native set, where they substitute.
              # Otherwise each one drags its own closure into the cross build:
              # libcap alone costs pam -> audit -> gawk plus
              # systemd/util-linux/sqlite/tcl, and bash costs readline and
              # ncurses.
              kselftests = prev.kselftests.override { targetPkgs = guestPkgs.aarch64-linux; };
            }
          );
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

          inherit (pkgs)
            kselftests
            blktests
            test-runner
            ktests
            kstresstests
            ;

          lk-vm = pkgs.callPackage ./lk-vm {
            inherit self guestPkgs guestCrossPkgs;
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
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
          # Cross-compiled kselftests, to iterate on the cross build without
          # booting a guest. Same package set the aarch64 guest uses, so this is
          # the same derivation.
          kselftests-aarch64 = guestCrossPkgs.aarch64-linux.kselftests;
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
              mergiraf
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
      # Modify the writeShellApplication helper to replace its checkPhase (which
      # normally calls shellcheck) with a nop.
      overlays.noShellcheck = final: prev: {
        writeShellApplication =
          args:
          (prev.writeShellApplication args).overrideAttrs (old: {
            nativeBuildInputs = final.lib.filter (
              x: !final.lib.hasInfix "shellcheck" (final.lib.toLower (x.name or ""))
            ) (old.nativeBuildInputs or [ ]);
            checkPhase = ":";
          });
      };

      # Test packages, as an overlay so they build for whatever package set
      # they're applied to (the per-system `pkgs` and the lk-vm guests). Building
      # from `final` rather than pulling out of `self.packages.<system>` means
      # each package set builds its own, for its own platform.
      overlays.guest = final: prev: {
        # Little tool for running tests.
        test-runner = final.callPackage ./test-runner { };
        # Version of kselftests built from the nixpkgs kernel.
        kselftests = final.callPackage ./kselftests.nix { kernelSrc = kernel; };
        blktests = final.callPackage ./blktests.nix { inherit inputs; };
        # Some experimental tools for stress-testing. This is different from
        # ktests in that they run continuously so they never produce a "pass"
        # signal.
        kstresstests = final.callPackage ./kstresstests.nix { };
        # Tool plus a config to run some kernel tests.
        ktests = final.callPackage ./ktests.nix { };
      };
    };
}
