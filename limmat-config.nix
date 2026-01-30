{
  lib,
  pkgs,

  # Required args
  lk-vm,
  lk-kconfig,
}:
let
  # For simplicity, all the scripts just have a common set of runtimeInputs.
  # This will also be exported in order to expose that stuff to the devShell.
  # Note that these runtimeInputs are special, not like the normal
  # writeShellApplication runtimeInputs: as well as stuff being in $PATH, stuff
  # like CFLAGS is also set up via the stdenv, so that you can use C libraries
  # here too.
  runtimeInputs = (
    with pkgs;
    [
      # Kernel build deps
      gnumake
      gcc
      flex
      bc
      bison
      elfutils

      qemu # For kunit.py
      ccache
      # checkpatch.py needs python. checkatch.pl calls spdxcheck.py which uses
      # ply and gitpython.
      (python3.withPackages (
        py-pkgs: with py-pkgs; [
          ply
          gitpython
        ]
      ))
      perl
      git
      codespell
    ]
  );
  # Helper to generate a script with the runtimeInputs in its environment.
  # Outputs the full path of the script itself, not the overall derivation.
  #
  # This really unholy. What we're trying to do here is something a bit like
  # writeShellApplication, but with the terrible seed of devShell planted in it.
  # So as well as injecting the runtimeInputs into $PATH, it also does the stuff
  # that a development shell would have, so that C libraries are available to
  # the compiler etc. None of this at all resembles how the fuck Nix is actually
  # supposed to be used.
  mkTestScript =
    {
      name,
      text,
    }@args:
    let
      pkg = pkgs.stdenv.mkDerivation rec {
        name = "limmat-kernel_${args.name}";

        # So the actual way we get the correct variables set up is by sourcing
        # the setup script of the stdenv. This is the really fucked up bit right
        # here, you are not supposed to be randomly sourcing this at built time,
        # which is why we need to set some random internal variables to make it
        # even work.
        # One way to try to mitigate this hell might be be: instead of
        # forwarding the NIX_ variables from the installPhase and then using
        # them to influence the stdenv at runtime, just forward the end result
        # of the stdenv by exporting the appropriate vars. The only reason I
        # haven't tried this is that I don't know what those vars are.
        src = pkgs.writeShellScript "${name}_script" ''
          set -o pipefail -o errexit -o nounset

          out=/tmp/dummy-nix-out
          dev=/tmp/dummy-nix-dev
          noDumpEnvVars=1
          export NIX_ENFORCE_PURITY=0
          source ${pkgs.buildPackages.stdenv}/setup

          export PATH="${lib.makeBinPath runtimeInputs}:$PATH"

          ${text}
        '';

        buildInputs = runtimeInputs;
        nativeBuildInputs = [ pkgs.makeWrapper ];

        # Disable most of the fancy stuff since this is a trivial derivation.
        dontUnpack = true;
        dontConfigure = true;
        dontBuild = true;

        installPhase = ''
          mkdir -p $out/bin
          cp $src $out/bin/${name}

          # Note it's important to use --set instead of --prefix here, as the
          # latter de-duplicates args so it will drop the -isystem args etc.
          wrapProgram $out/bin/${name} \
            --set NIX_CFLAGS_COMPILE "$NIX_CFLAGS_COMPILE" \
            --set NIX_LDFLAGS "$NIX_LDFLAGS" \
            --prefix PATH ":" "$PATH"
        '';
      };
    in
    builtins.toPath "${pkg}/bin/${pkg.name}";
  # Helper to generate a test script that runs a kernel build.
  mkBuild =
    {
      name,
      configFrags,
      extraConfigs ? [ ],
      # Skip the test if this string doesn't appear in the repo.
      ifContains ? "",
    }:
    {
      name = "build_${name}";
      cache = "by_tree";
      command = mkTestScript {
        inherit name;
        text =
          let
            fragsStr = lib.concatStringsSep " " configFrags;
            enablesStr = lib.concatStringsSep " " extraConfigs;
          in
          ''
            set -eux

            # shellcheck disable=SC2157
            if [[ -n "${ifContains}" ]] && ! git grep -q "${ifContains}"; then
              touch "$LIMMAT_ARTIFACTS"/skipped
              exit 0
            fi

            ${lk-kconfig}/bin/lk-kconfig --frags "${fragsStr}" --enable "${enablesStr}"
            make -sj"$(nproc)" bzImage CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= W=1 2>&1
            mv arch/x86/boot/bzImage "$LIMMAT_ARTIFACTS"
          '';
      };
    };
  # Helper script for running ktests in a test job. 1st arg is artifacts from
  # build job. 2nd arg is args to pass to lk-vm's ktest arg. 3rd arg is extra
  # kernel args.
  run-ktests = pkgs.writeShellApplication {
    runtimeInputs = [
      pkgs.coreutils
      lk-vm
    ];
    name = "run-ktests";
    text = ''
      set -eux

      BUILD_ARTIFACTS="$1"
      KTEST_ARGS="$2"
      KERNEL_ARGS="$3"

      if [[ -e "$BUILD_ARTIFACTS"/skipped ]]; then
        # Kernel wasn't built, don't try to run it.
        exit 0
      fi
      kernel="$BUILD_ARTIFACTS"/bzImage

      # Hack: the NixOS QEMU script by default uses ./$hostname.qcow2 for
      # its disk. Switch to a tempdir to avoid sharing that (we have
      # needs_worktree = false so we are running in the original source
      # directory).
      tmpdir="$(mktemp -d)"
      pushd "$tmpdir"
      trap 'popd && rm -rf $tmpdir' EXIT

      # 0x20 means is TAINT_BAD_PAGE.
      timeout --signal=KILL 600s \
        ${lk-vm}/bin/lk-vm --kernel "$kernel" --ktests="$KTEST_ARGS" \
        --ktests-output="$LIMMAT_ARTIFACTS" \
        --cmdline "$KERNEL_ARGS panic_on_warn=1 panic_on_taint=0x20"
    '';
  };
in
{
  # Why does this need to return everything inside a ".config" field instead of
  # just directly returning the config? Well, let me explain. Basically, it's
  # quite simple. Quite simply, I do not know. I don't know why this is needed.
  # I think it's some sort of outcome of the Nix black magic that goes on with
  # callPackage. If you try to serialise the direct result of this package into
  # JSON it will fail because it's actually some Nix black magic and not just a
  # normal attribute set. But if you instead access an attribute of the returned
  # value then you get a nice red blooeded American attrset.
  config = {
    num_worktrees = 8;
    resources = [
      # Don't run too many QEMUs at once.
      {
        name = "qemu_throttle";
        count = 1;
      }
      # Don't DoS the build service.
      {
        name = "kbs";
        count = 8;
      }
    ];

    tests =
      let
        mkGbuild = name: args: {
          inherit name;
          requires_worktree = false;
          resources = [ "kbs" ];
          command = ''gbuild2 --need_local_outputs=false --remote --commit="$LIMMAT_COMMIT" ${args}'';
          run_by_default = false;
        };
      in
      [
        # Ultra minimal - this shouldn't even enable 64bit
        (
          mkBuild {
            name = "32";
            configFrags = [ "base" ];
          }
          // {
            depends_on = [ "ksft" ]; # Hack to deprioritise
          }
        )
        # Minimal kernel for running kselftests in a NixOS VM
        (mkBuild {
          name = "ksft";
          configFrags = [
            "base"
            "compile"
            "vm-boot"
            "kselftests"
            "debug"
          ];
        })
        (mkBuild {
          name = "asi";
          ifContains = "CONFIG_MITIGATION_ADDRESS_SPACE_ISOLATION";
          configFrags = [
            "base"
            "compile"
            "vm-boot"
            "kselftests"
            "debug"
            "asi"
          ];
        })
        (mkGbuild "gb" "")
        (mkGbuild "gb_arm" "ARCH=arm64")
        (mkGbuild "gb_dbg" "CONFIG=dbg")
        {
          name = "ksft";
          cache = "by_tree";
          depends_on = [ "build_ksft" ]; # Defined by a mkBuild call with name = "ksft"
          resources = [ "qemu_throttle" ];
          requires_worktree = false;
          # With ASI compiled out, not much point in running too many tests,
          # just run the mm ones since that's the stuff the ASI patchs are most
          # likely to break.
          command = ''${run-ktests}/bin/run-ktests "$LIMMAT_ARTIFACTS_build_ksft" "*" ""'';
        }
        {
          name = "kunit_x86";
          cache = "by_tree";
          resources = [ "qemu_throttle" ];
          command = mkTestScript {
            name = "kunit_x86";
            text = ''
              set -eux

              make mrproper
              rm -rf .kunit/  # Clear leftover .kunitconfig
              tools/testing/kunit/kunit.py run --arch=x86_64
            '';
          };
        }
        {
          name = "ksft_asi_off";
          cache = "by_tree";
          depends_on = [ "build_asi" ]; # Defined by a mkBuild call with name = "asi"
          resources = [ "qemu_throttle" ];
          requires_worktree = false;
          # Just want to check boot really, pick some arbitrary test that's quick
          # and reliable.
          command = ''${run-ktests}/bin/run-ktests "$LIMMAT_ARTIFACTS_build_asi" "*" "asi=off"'';
          run_by_default = false;
        }
        {
          name = "ksft_asi";
          cache = "by_tree";
          depends_on = [ "build_asi" ]; # Defined by a mkBuild call with name = "asi"
          resources = [ "qemu_throttle" ];
          requires_worktree = false;
          command = ''${run-ktests}/bin/run-ktests "$LIMMAT_ARTIFACTS_build_asi" "*" "asi=on"'';
          run_by_default = false;
        }
        {
          name = "kunit_asi";
          cache = "by_tree";
          resources = [ "qemu_throttle" ];
          run_by_default = false;
          command = mkTestScript {
            name = "kunit_asi";
            text = ''
              set -eux

              for kunitconfig in arch/x86/mm/.kunitconfig arch/x86/.kunitconfig; do
                if [[ -e "$kunitconfig" ]]; then
                  make mrproper
                  tools/testing/kunit/kunit.py run --arch=x86_64 \
                    --kunitconfig "$kunitconfig" --kernel_args asi=on
                  grep ADDRESS_SPACE_ISOLATION .kunit/.config
                fi
              done
            '';
          };
        }
        {
          name = "checkpatch";
          # HACK: See comments on LIMMAT_NOTES_OBJECT in checkpatch.py.
          cache = "no_caching";
          command = mkTestScript {
            name = "checkpatch";
            text = "python ${./checkpatch.py}";
          };
        }
        {
          name = "todo";
          requires_worktree = false;
          command = mkTestScript {
            name = "checkpatch";
            text = ''
              set -ux +e

              git show "$LIMMAT_COMMIT" | grep TODO
              status=$?
              if [[ "$status" == 1 ]]; then
                exit 0  # no matches
              elif [[ "$status" == 0 ]]; then
                exit 1  # matches
              fi
              # error
            '';
          };
        }
      ];
  };
  inherit runtimeInputs;
}
