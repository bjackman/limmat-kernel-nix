{
  lib,
  pkgs,
  writeShellScript,
  writeShellApplication,
  mkShell,
  linuxPackages,
}:
{
  config = {
    tests = [
      {
        name = "build_min";
        command =
          let
            script = writeShellScript "build_min" ''
              make -j tinyconfig
              scripts/config -e 64BIT -e -WERROR -e OBJTOOL_WERROR
              make -j olddefconfig
              make -sj"$(nproc)" vmlinux CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= 2>&1
            '';
            kernelDevShell = mkShell {
              inputsFrom = [ linuxPackages.kernel ];
              packages = [ pkgs.ccache ];
            };
          in
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
          "${writeShellScript "nix-develop_build_min" ''
            ${pkgs.nix}/bin/nix develop ${kernelDevShell.drvPath} --command ${script}
          ''}";
      }
    ];
  };
}
