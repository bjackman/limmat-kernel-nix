#!/bin/sh

# This script installs the Nix package manager on your system by
# downloading a binary distribution and running its installer script
# (which in turn creates and populates /nix).

{ # Prevent execution if this script was only partially downloaded
oops() {
    echo "$0:" "$@" >&2
    exit 1
}

umask 0022

tmpDir="$(mktemp -d -t nix-binary-tarball-unpack.XXXXXXXXXX || \
          oops "Can't create temporary directory for downloading the Nix binary tarball")"
cleanup() {
    rm -rf "$tmpDir"
}
trap cleanup EXIT INT QUIT TERM

require_util() {
    command -v "$1" > /dev/null 2>&1 ||
        oops "you do not have '$1' installed, which I need to $2"
}

case "$(uname -s).$(uname -m)" in
    Linux.x86_64)
        hash=311b9f406f0239ef640a1e3fbea1df1bac9d3a7c316c4def30df3206dd964960
        path=80z2bk3in4rr4p8l6fkab6q7hib2j9ky/nix-2.34.6-x86_64-linux.tar.xz
        system=x86_64-linux
        ;;
    Linux.i?86)
        hash=f74f903a115326f8fdbd887d17b404c7387c6192e63a8632642e014ff73fe9f3
        path=szh30jp37yvljn6d1rx39yi0kkl0w3kl/nix-2.34.6-i686-linux.tar.xz
        system=i686-linux
        ;;
    Linux.aarch64)
        hash=09edae3ed146b1a47de84eda6135ef12ee74783d409e7a207c912cb94e14aa35
        path=1mjykgnx3dibmk6swwb5yszvnji7mfa5/nix-2.34.6-aarch64-linux.tar.xz
        system=aarch64-linux
        ;;
    Linux.armv6l)
        hash=2df268e60e8357fd8fb18eb954e007f22e053a4c52a37b7ac693ca2c71b1459c
        path=6lhx2qbxvzws330lfbb2vadrx45vs0xh/nix-2.34.6-armv6l-linux.tar.xz
        system=armv6l-linux
        ;;
    Linux.armv7l)
        hash=72ffe695b47cc46fc912e0fa60a17c55eeb269409f844efac71db94b5451edff
        path=s0jvnhh6205pnx11xgszb61k30cip98d/nix-2.34.6-armv7l-linux.tar.xz
        system=armv7l-linux
        ;;
    Linux.riscv64)
        hash=8672fc98c6a9c549a53f4c3ddb21b91e6ae1d40ae547ddab50c2e1a676b20d92
        path=3kkz526yn39s1lip0l8jakbs1vzxv0l8/nix-2.34.6-riscv64-linux.tar.xz
        system=riscv64-linux
        ;;
    Darwin.x86_64)
        hash=ae58c8c91e3951602869e5a502621edb1bdde8ab20436f488a29af6a0aecd846
        path=jcjnr3xdvzckd7wdq42rvwqxj4ibf6s8/nix-2.34.6-x86_64-darwin.tar.xz
        system=x86_64-darwin
        ;;
    Darwin.arm64|Darwin.aarch64)
        hash=596ae5555acfb497723934b98b66b7d638eb8f7d856975466f2c1217ce94f8a1
        path=j2i48nfwlaynkwiafjqn4971s6gcv4fa/nix-2.34.6-aarch64-darwin.tar.xz
        system=aarch64-darwin
        ;;
    *) oops "sorry, there is no binary distribution of Nix for your platform";;
esac

# Use this command-line option to fetch the tarballs using nar-serve or Cachix
if [ "${1:-}" = "--tarball-url-prefix" ]; then
    if [ -z "${2:-}" ]; then
        oops "missing argument for --tarball-url-prefix"
    fi
    url=${2}/${path}
    shift 2
else
    url=https://releases.nixos.org/nix/nix-2.34.6/nix-2.34.6-$system.tar.xz
fi

tarball=$tmpDir/nix-2.34.6-$system.tar.xz

require_util tar "unpack the binary tarball"
if [ "$(uname -s)" != "Darwin" ]; then
    require_util xz "unpack the binary tarball"
fi

if command -v curl > /dev/null 2>&1; then
    fetch() { curl --fail -L "$1" -o "$2"; }
elif command -v wget > /dev/null 2>&1; then
    fetch() { wget "$1" -O "$2"; }
else
    oops "you don't have wget or curl installed, which I need to download the binary tarball"
fi

echo "downloading Nix 2.34.6 binary tarball for $system from '$url' to '$tmpDir'..."
fetch "$url" "$tarball" || oops "failed to download '$url'"

if command -v sha256sum > /dev/null 2>&1; then
    hash2="$(sha256sum -b "$tarball" | cut -c1-64)"
elif command -v shasum > /dev/null 2>&1; then
    hash2="$(shasum -a 256 -b "$tarball" | cut -c1-64)"
elif command -v openssl > /dev/null 2>&1; then
    hash2="$(openssl dgst -r -sha256 "$tarball" | cut -c1-64)"
else
    oops "cannot verify the SHA-256 hash of '$url'; you need one of 'shasum', 'sha256sum', or 'openssl'"
fi

if [ "$hash" != "$hash2" ]; then
    oops "SHA-256 hash mismatch in '$url'; expected $hash, got $hash2"
fi

unpack=$tmpDir/unpack
mkdir -p "$unpack"
tar -xJf "$tarball" -C "$unpack" || oops "failed to unpack '$url'"

script=$(echo "$unpack"/*/install)

[ -e "$script" ] || oops "installation script is missing from the binary tarball!"
export INVOKED_FROM_INSTALL_IN=1
"$script" "$@"

} # End of wrapping
