{
  lib,
  pkgs,
  writeShellApplication,
}:
{
  config =
    # Helper to make a derivation that runs a script in an environment with a
    # bunch of useful stuf available.
    let
      writeBuildScript =
        { name, text }:
        writeShellApplication rec {
          inherit name;
          inherit text;
          # TODO: Currently describing the build env completely manually.
          # This might actually be a desirable way to do it, but maybe it's
          # way more sensible to try to more directly expose the build env
          # of the NixOS kernel package. I just haven't figured out how to
          # do that.
          runtimeInputs = with pkgs; [
            # Basic shit that is included by default in the stdenv. I'm not
            # sure if it's really expected that these are needed but
            # including them lets me test with `nix run --unset PATH` to
            # check purity which is nice.
            bash
            coreutils
            gnused
            gnumake
            gnugrep
            diffutils
            gawk
            findutils

            # The core kernel build deps.
            gcc
            bison
            flex
            perl
            bc
            openssl
            elfutils
            cpio
            libelf

            # Other stuff.
            ccache
          ];
          # TODO: Even if we did actually prefer to build the environment
          # quite manually, it seems unlikely that specifying these
          # variables completely explicitly like this would really be
          # necessary, but I'm not sure how this happens magically in
          # nixpkgs when you specify a library as a buildInput. Maybe that
          # magic can be reused here or maybe not. I think that magic is to
          # do with the obtusely-documented "Package setup hooks". Those are
          # specified as being unstable between Nixpkgs releases so maybe
          # doing it manually like this really is preferred...
          # https://nixos.org/manual/nixpkgs/stable/#ssec-setup-hooks
          runtimeEnv = {
            # Set HOSTCFLAGS to point to all the necessary headers to build
            # host binaries.
            HOSTCFLAGS =
              let
                # Headers are generally in the .dev output of the package,
                # but no all packages have this output. So this function
                # returns the necessary '-system flag' for packages that
                # have it and null for the ones that don't.
                getCflags = pkg: if builtins.hasAttr "dev" pkg then "-isystem ${pkg.dev}/include" else null;
              in
              lib.concatStringsSep " " (builtins.filter (x: x != null) (map getCflags runtimeInputs));
            # Define HOSTLDFLAGS so we can link against libraries when
            # building host stuff. This is a bit simpler because we can
            # assume that all the packages have a .out output.
            HOSTLDFLAGS = lib.concatStringsSep " " (map (pkg: "-I ${pkg.out}/lib") runtimeInputs);
          };
        };
    in
    {
      tests = [
        {
          name = "build_min";
          command =
            let
              pkg = writeBuildScript {
                name = "test-build_min";
                text = ''
                make -j tinyconfig
                scripts/config -e 64BIT -e -WERROR -e OBJTOOL_WERROR
                make -j olddefconfig
                CCACHE_SLOPPINESS=time_macros make -sj"$(nproc)" vmlinux CC='ccache gcc' KBUILD_BUILD_TIMESTAMP= 2>&1
                '';
              };
            in
            "${pkg}/bin/test-build_min";
        }
      ];
    };
}