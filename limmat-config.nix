{
  lib,
  pkgs,
  writeShellScript,
  writeShellApplication,
  linuxPackages,
  kernelDevShell,
}:
let
  # Alright, so we are gonna want to define a devShell anyway. And
  # devShells include all the necessary magic for setting up the build
  # environment, which you don't usually get at runtime: for example, if
  # you set up openssl as a runtime dependency of the script, the
  # library will be there but it won't be set up in your LDFLAGS or
  # whatever. So it really makes sense to want to run the script in a
  # devShell (after all, the whole idea of Limmat is that it encodes
  # "tests" that are similar to what you run in your interactive shell).
  # How do you run something inside a devShell (at runtime)? I'm not
  # sure. As best I can tell, the thing that mkShell produces is not
  # really considered API - there is text at the top of it saying so.
  # It's considered an internal implementation detail of 'nix-shell' and
  # 'nix develop'. So.... let's just call `nix develop`...? I'm pretty
  # sure there are gonna be sketchy consequences of this but I'm not
  # really sure what they will be.
  # OKAY: one of the sketchy outcomes of this is that we cannot run this
  # inside the Nix build sandbox. This prevents us from defining a flake
  # check that verifies the configuration. Hmm.
  mkDevShellScript =
    name: text:
    writeShellScript "nix-develop_${name}" ''
      ${pkgs.nix}/bin/nix develop ${kernelDevShell.drvPath} --command ${writeShellScript name text}
    '';
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
    tests = [
      {
        name = "build_min";
        command = mkDevShellScript "build_min" ''
          set -eux

          make -j tinyconfig
          scripts/config -e 64BIT -e -WERROR -e OBJTOOL_WERROR
          make -j olddefconfig
          make -sj"$(nproc)" vmlinux CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= 2>&1
        '';
      }
    ];
  };
}
