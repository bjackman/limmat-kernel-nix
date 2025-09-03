{
  lib,
  pkgs,
}:
# In a former life I tried to define this all hermetically so that all the
# dependencies were captured and the configuration's hash would change whenever
# I modified anything.
# For now I've given up on that, and this just assumes you are running it from
# the devShell defined in the top of this repo.
let
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
      command = ''
        set -eux

        if [[ -n "${ifContains}" ]] && ! git grep -q "${ifContains}"; then
          exit 0
        fi

        limmat-kernel-vm-kconfig -b ${base} ${lib.concatMapStringsSep " " (elem: "-e ${elem}") configs}
        make -sj"$(nproc)" vmlinux CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= 2>&1
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
    tests = [
      (mkBuild {
        name = "32";
        base = "tinyconfig";
      })
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
          "CMA"
        ];
      })
    ];
  };
}
