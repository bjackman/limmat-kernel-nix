{
  lib,
  pkgs,
  writeShellScript,
  writeShellApplication,
  linuxPackages,
  kernelDevShell,
}:
# In a former life I tried to define this all hermetically so that all the
# dependencies were captured and the configuration's hash would change whenever
# I modified anything.
# For now I've given up on that, and this just assumes you are running it from
# the devShell defined in the top of this repo.
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
    tests = [
      {
        name = "build_min";
        command = ''
          set -eux

          limmat-kernel-vm-kconfig -b tinyconfig -e 64BIT -e -WERROR -e OBJTOOL_WERROR
          make -sj"$(nproc)" vmlinux CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= 2>&1
        '';
      }
    ];
  };
}
