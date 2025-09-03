{
  lib,
  pkgs,

  # Required args
  vm-run,
  vm-kconfig,
}:
# In a former life I tried to define this all hermetically so that all the
# dependencies were captured and the configuration's hash would change whenever
# I modified anything.
# For now I've given up on that, and this just assumes you are running it from
# the devShell defined in the top of this repo.
let
  # For simplicity, all the scripts just have a common set of runtimeInputs.
  # This will also be exported in order to expose that stuff to the devShell.
  runtimeInputs = [ pkgs.ccache ];
  # Helper to generate a script with the runtimeInputs in its environment.
  # Outputs the full path of the script itself, not the overall derivation.
  mkTestScript =
    {
      name,
      text,
    }:
    let
      appName = "limmat-kernel_${name}";
    in
    "${
      pkgs.writeShellApplication {
        inherit runtimeInputs text;
        name = appName;
      }
    }/bin/${appName}";
  # Helper to generate a test script that runs a kernel build.
  mkBuild =
    {
      name,
      base,
      configs ? [ ],
      # Skip the test if this string doesn't appear in the repo.
      ifContains ? "",
    }:
    {
      name = "build_${name}";
      cache = "by_tree";
      command = mkTestScript {
        inherit name;
        text = ''
          set -eux

          # shellcheck disable=SC2157
          if [[ -n "${ifContains}" ]] && ! git grep -q "${ifContains}"; then
            touch "$LIMMAT_ARTIFACTS"/skipped
            exit 0
          fi

          ${vm-kconfig}/bin/limmat-kernel-vm-kconfig -b ${base} ${
            lib.concatMapStringsSep " " (elem: "-e ${elem}") configs
          }
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
      (
        mkBuild {
          name = "32";
          base = "tinyconfig";
        }
        // {
          depends_on = [ "kselftests" ]; # Hack to deprioritise
        }
      )
      (mkBuild {
        name = "min";
        # Hm OK this isn't really that minimal, it's enough to boot a VM.
        # Maybe we want a really really fast 64-bit build too (no
        # kvm_guest.config)?
        # TODO: This is my attempt to find a config that boots but it's not
        # enough, something is missing.
        base = "tinyconfig kvm_guest.config";
        configs = [
          "64BIT"
          "WERROR"
          "OBJTOOL_WERROR"
          "OVERLAY_FS"
          # TODO: Which ones of these are actually needed?
          "MISC_FILESYSTEMS" # TODO: This is just a dependency
          "SQUASHFS"
          "FUSE_FS" # TODO: This is just a dependency
          "VIRTIO_FS"
          "PROC_FS"
          "PROC_KCORE"
          "VIRTIO_MENU" # TODO: This is just a dependency
          "VIRTIO_MMIO"
          "BLOCK" # TODO: This is just a dependency
          "BLK_DEV_SD"
          "SCSI" # TODO: This is just a dependency
          "SCSI_VIRTIO"
          "ACPI"
          # TODO: Disable WLAN and ETHERNET
        ];
      })
      (mkBuild {
        name = "asi";
        base = "defconfig";
        ifContains = "CONFIG_MITIGATION_ADDRESS_SPACE_ISOLATION";
        configs = [
          "MITIGATION_ADDRESS_SPACE_ISOLATION"
          "DEBUG_LIST"
          "DEBUG_VM"
          "CMA"
        ];
      })
      {
        name = "kselftests";
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

          # Hack: the NixOS QEMU script by default uses ./$hostname.qcow2 for
          # its disk. Switch to a tempdir to avoid sharing that (we have
          # needs_worktree = false so we are running in the original source
          # directory).
          tmpdir="$(mktemp -d)"
          pushd "$tmpdir"
          trap "popd && rm -rf $tmpdir" EXIT

          timeout --signal=KILL 60s \
            ${vm-run}/bin/limmat-kernel-vm-run --kernel "$kernel" --kselftests
        '';
      }
    ];
  };
}
