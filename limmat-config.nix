{
  lib,
  pkgs,

  # Required args
  lk-vm,
  lk-kconfig,
}:
# In a former life I tried to define this all hermetically so that all the
# dependencies were captured and the configuration's hash would change whenever
# I modified anything.
# For now I've given up on that, and this just assumes you are running it from
# the devShell defined in the top of this repo.
let
  # For simplicity, all the scripts just have a common set of runtimeInputs.
  # This will also be exported in order to expose that stuff to the devShell.
  runtimeInputs = (with pkgs; [
    ccache
    # checkpatch.py deps:
    python3
    perl
    git
    codespell
  ]);
  # Helper to generate a script with the runtimeInputs in its environment.
  # Outputs the full path of the script itself, not the overall derivation.
  mkTestScript =
    {
      name,
      text,
    }:
    let
      appName = "limmat-kernel_${name}";
      # Hack to workaround awkward Limmat behaviour: stderr and stdout are
      # stored together we no feature to merge them.
      appText = ''
        exec 2>&1
        ${text}
      '';
    in
    "${
      pkgs.writeShellApplication {
        inherit runtimeInputs;
        name = appName;
        text = appText;
      }
    }/bin/${appName}";
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
            make -sj"$(nproc)" bzImage CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= 2>&1
            mv arch/x86/boot/bzImage "$LIMMAT_ARTIFACTS"
          '';
      };
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
      # When I run lots of QEMUs I sometimes see the guest complain that the
      # IOAPIC is broken. Trying throttling to 1 at a time...
      {
        name = "qemu_throttle";
        count = 1;
      }
    ];

    tests = [
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
          "vm-boot"
          "kselftests"
        ];
      })
      (mkBuild {
        name = "asi";
        ifContains = "CONFIG_MITIGATION_ADDRESS_SPACE_ISOLATION";
        configFrags = [
          "base"
          "vm-boot"
          "kselftests"
          "asi"
        ];
      })
      {
        name = "ksft";
        cache = "by_tree";
        depends_on = [ "build_ksft" ]; # Defined by a mkBuild call with name = "ksft"
        resources = [ "qemu_throttle" ];
        requires_worktree = false;
        command = ''
          set -eux

          # Hack: the NixOS QEMU script by default uses ./$hostname.qcow2 for
          # its disk. Switch to a tempdir to avoid sharing that (we have
          # needs_worktree = false so we are running in the original source
          # directory).
          tmpdir="$(mktemp -d)"
          pushd "$tmpdir"
          trap "popd && rm -rf $tmpdir" EXIT

          timeout --signal=KILL 60s \
            ${lk-vm}/bin/lk-vm --kernel "$LIMMAT_ARTIFACTS_build_ksft/bzImage" --kselftests
        '';
      }
      {
        name = "ksft_asi";
        cache = "by_tree";
        depends_on = [ "build_asi" ]; # Defined by a mkBuild call with name = "asi"
        resources = [ "qemu_throttle" ];
        requires_worktree = false;
        command = ''
          set -eux

          if [[ -e "$LIMMAT_ARTIFACTS_build_asi"/skipped ]]; then
            # Kernel wasn't built, don't try to run it.
            exit 0
          fi
          kernel="$LIMMAT_ARTIFACTS_build_asi"/bzImage

          tmpdir="$(mktemp -d)"
          pushd "$tmpdir"
          trap "popd && rm -rf $tmpdir" EXIT

          # 0x20 means is TAINT_BAD_PAGE.
          timeout --signal=KILL 60s \
            ${lk-vm}/bin/lk-vm --kernel "$kernel" --kselftests \
            --cmdline "asi=on panic_on_warn=1 panic_on_taint=0x20"
        '';
      }
      {
        name = "kunit_asi";
        cache = "by_tree";
        resources = [ "qemu_throttle" ];
        command = ''
          set -eux

          kunitconfig=arch/x86/mm/.kunitconfig
          if [[ ! -e "$kunitconfig" ]]; then
            exit 0
          fi

          make mrproper
          tools/testing/kunit/kunit.py run --arch=x86_64 \
            --kunitconfig=arch/x86/mm/.kunitconfig --kernel_args asi=on
        '';
      }
      {
        name = "checkpatch";
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
}
