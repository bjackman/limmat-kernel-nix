{ pkgs, writeShellApplication }:
{
  config = {
    tests = [
      {
        name = "build_min";
        command =
          let
            pkg = writeShellApplication rec {
              name = "test-build_min";
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
              extraShellCheckFlags = [
                "--external-sources"
                "--source-path=${pkgs.stdenv}"
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
                HOSTCFLAGS = "-isystem ${pkgs.elfutils.dev}/include -isystem ${pkgs.openssl.dev}/include";
                HOSTLDFLAGS = "-L ${pkgs.elfutils.out}/lib -L ${pkgs.openssl.out}/lib";
              };
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
