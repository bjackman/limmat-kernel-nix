{ pkgs ? import <nixpkgs> {} }:
pkgs.llvmPackages.stdenv.mkDerivation {
  name = "test";
  src = ./.;
  buildPhase = ''
    echo CC=$CC
    echo HOSTCC=$HOSTCC
  '';
}
