{ pkgs, lk-kconfig, kernelSrc }:
pkgs.stdenv.mkDerivation {
  name = "golden-kernel";
  src = kernelSrc;
  nativeBuildInputs = with pkgs; [
    bison flex bc elfutils openssl
    lk-kconfig
  ];
  buildPhase = ''
    patchShebangs scripts
    # We need to copy source to a writable dir because src is read-only
    cp -r $src/* .
    chmod -R u+w .

    lk-kconfig --frags "base vm-boot kselftests debug"
    make -j$NIX_BUILD_CORES bzImage
  '';
  installPhase = ''
    install -D arch/x86/boot/bzImage $out/bzImage
  '';
}
