{
  pkgs,
  lk-kconfig,
  kernelSrc,
}:
pkgs.stdenv.mkDerivation {
  name = "golden-kernel";
  src = kernelSrc;
  nativeBuildInputs = with pkgs; [
    bison
    flex
    bc
    elfutils
    openssl
    lk-kconfig
    pahole
    python3
    zlib
    perl
  ];
  postPatch = ''
    patchShebangs .
  '';
  buildPhase = ''
    lk-kconfig --frags "x86 base vm-boot kselftests debug kselftests/bpf"
    make -j$NIX_BUILD_CORES bzImage vmlinux
  '';
  installPhase = ''
    install -D arch/x86/boot/bzImage $out/bzImage
    install -D vmlinux $out/vmlinux
  '';
}
