# Builds kselftests from a given kernel source. Currently this only actually
# does the mm ones. The kselftest build is a big mess so more work is needed for
# each set of targets we wanna build.
{
  pkgs,
  lib,
  fetchpatch,
  stdenv,

  # Explicit args.
  kernelSrc,
}:
let
  isX86_64 = stdenv.hostPlatform.system == "x86_64-linux";
  buildStdenv = if isX86_64 then pkgs.multiStdenv else stdenv;

  # Map Nix system to kernel ARCH
  kernelArch = stdenv.hostPlatform.linuxArch;
  kernelCrossCompile = stdenv.cc.targetPrefix;

  # On 32-bit most stuff doesn't compile. On x86_64 I can build this subset of
  # kselftests. Assume that that will work on other systems too, although they
  # probably don't really.
  # TODO build the rest too
  kselftestsTargets =
    if stdenv.hostPlatform.system == "i686-linux" then
      "x86"
    else if isX86_64 then
      "kvm mm x86"
    else
      "kvm mm";
in
buildStdenv.mkDerivation {
  name = "kselftests";
  src = kernelSrc;
  nativeBuildInputs = with pkgs; [
    bison
    flex
    rsync
    makeWrapper
  ];
  buildInputs = with pkgs; [
    libcap
    numactl
    binutils # For addr2line, see wrapProgram call
    bash # Added so patchShebangs --host can find the target bash
  ];
  enableParallelBuilding = true;
  postPatch = ''
    patchShebangs scripts
  '';
  # Need to set -j explicitly because it doesn't go into the $makeFlags until
  # buildPhase.
  configurePhase = ''
    make -j$NIX_BUILD_CORES defconfig \
      ARCH=${kernelArch} \
      CROSS_COMPILE=${kernelCrossCompile} \
      HOSTCC=${pkgs.buildPackages.stdenv.cc}/bin/cc
    scripts/config -e GUP_TEST
    make olddefconfig \
      ARCH=${kernelArch} \
      CROSS_COMPILE=${kernelCrossCompile} \
      HOSTCC=${pkgs.buildPackages.stdenv.cc}/bin/cc
    grep GUP_TEST .config
  '';
  preBuild = ''
    make -j$NIX_BUILD_CORES headers \
      ARCH=${kernelArch} \
      CROSS_COMPILE=${kernelCrossCompile} \
      HOSTCC=${pkgs.buildPackages.stdenv.cc}/bin/cc
  ''
  + (
    if isX86_64 then
      ''
        export NIX_LDFLAGS="-L${pkgs.glibc_multi.out}/lib/32 -L${pkgs.glibc_multi.static}/lib -L${pkgs.glibc_multi.static}/lib64 $NIX_LDFLAGS"
        export LIBRARY_PATH="${pkgs.glibc_multi.out}/lib/32:${pkgs.glibc_multi.static}/lib:${pkgs.glibc_multi.static}/lib64:$LIBRARY_PATH"
      ''
    else if stdenv.hostPlatform.system == "i686-linux" then
      ''
        export NIX_LDFLAGS="-L${pkgs.glibc.static}/lib $NIX_LDFLAGS"
        export LIBRARY_PATH="${pkgs.glibc.static}/lib:$LIBRARY_PATH"
      ''
    else
      ''
        # For aarch64-linux (and others), we don't use static glibc by default to avoid linker issues.
        true
      ''
  )
  + ''
    # Need to set this in shell code, there's no way to pass flags with spaces
    # otherwise lmao i don fuken no m8 wo'eva
    makeFlagsArray+=("TARGETS=${kselftestsTargets}")
    makeFlagsArray+=("EXTRA_CFLAGS=-Wno-error=unused-result -fomit-frame-pointer -I../")
    makeFlagsArray+=("ARCH=${kernelArch}")
    makeFlagsArray+=("CROSS_COMPILE=${kernelCrossCompile}")
    makeFlagsArray+=("HOSTCC=${pkgs.buildPackages.stdenv.cc}/bin/cc")
  '';
  # Note these flags get re-used for both the buildPhase and the configurePhase.
  makeFlags = [
    "-C"
    "tools/testing/selftests"
    # I'm not entirely sure how that $(out) thing works, I copied it from
    # something I saw in the nixpkgs manual. We wanna set KSFT_INSTALL_PATH to
    # the value of the $out shell variable at runtime. My best guess is this is
    # just setting the literal string "$(out)" and then that's getting expanded
    # by Make.
    "KSFT_INSTALL_PATH=$(out)/bin"
    # Fail the build if the build fails, instead of just not outputting the tests.
    "FORCE_TARGETS=1"
    "V=1"
  ];
  preInstall = ''
    mkdir -p $out/bin
  '';

  postInstall =
    let
      deps = with pkgs; [
        # So that this can be run as a systemd service (where we don't inherit the
        # user's PATH), be very exhaustive about dependencies.
        which
        coreutils
        gnugrep
        gnused
        # KVM selftests calladdr2line if there's a failure.
        binutils
      ];
    in
    ''
      patchShebangs --host $out/bin
      wrapProgram $out/bin/run_kselftest.sh \
        --prefix PATH : "${lib.makeBinPath deps}"
    '';
}
