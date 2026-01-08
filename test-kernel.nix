{
  lib,
  pkgs,
  stdenv,
  bison,
  flex,
  bc,
  elfutils,
  lk-kconfig,
  kernelSrc,
}:

stdenv.mkDerivation {
  pname = "test-kernel";
  version = "0.0.0";

  src = kernelSrc;

  nativeBuildInputs = [
    bison
    flex
    bc
    elfutils
    lk-kconfig
  ];

  # Don't try to install modules, we just want the bzImage
  buildPhase = ''
    patchShebangs scripts/
    lk-kconfig "base vm-boot kdump debug"
    make -j$NIX_BUILD_CORES bzImage
  '';

  installPhase = ''
    mkdir -p $out
    cp arch/x86/boot/bzImage $out/bzImage
  '';
}
