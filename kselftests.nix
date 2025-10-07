# Builds kselftests from a given kernel source. Currently this only actually
# does the mm ones. The kselftest build is a big mess so more work is needed for
# each set of targets we wanna build.
{
  pkgs,
  lib,
  stdenv,
  fetchpatch,

  # Explicit args.
  kernelSrc,
}:
stdenv.mkDerivation {
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
  ];
  enableParallelBuilding = true;
  patches = [
    (fetchpatch {
      url = "https://github.com/bjackman/linux/commit/a3461dafc4bff0d22b34f4d22de2d06839e533c2.patch";
      hash = "sha256-PV9yZjrUrSROMVieGBPlfGKBM1i9NZY1nu1viaV5JMw=";
    })
  ];
  postPatch = ''
    patchShebangs scripts
  '';
  # Need to set -j explicitly because it doesn't go into the $makeFlags until
  # buildPhase.
  configurePhase = ''
    make -j$NIX_BUILD_CORES defconfig
    scripts/config -e GUP_TEST
    make olddefconfig
    grep GUP_TEST .config
  '';
  preBuild = ''
    make -j$NIX_BUILD_CORES headers
    # Need to set this in shell code, there's no way to pass flags with spaces
    # otherwise lmao i don fuken no m8 wo'eva
    makeFlagsArray+=("TARGETS=mm kvm") # TODO build the rest oo
  '';
  # Note these flags get re-used for both the buildPhase and the configurePhase.
  makeFlags = [
    "-C"
    "tools/testing/selftests"
    "EXTRA_CFLAGS=-Wno-error=unused-result"
    # I'm not entirely sure how that $(out) thing works, I copied it from
    # something I saw in the nixpkgs manual. We wanna set KSFT_INSTALL_PATH to
    # the value of the $out shell variable at runtime. My best guess is this is
    # just setting the literal string "$(out)" and then that's getting expanded
    # by Make.
    "KSFT_INSTALL_PATH=$(out)/bin"
  ];
  preInstall = ''
    mkdir -p $out/bin
  '';

  postInstall =
    let deps = with pkgs; [
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
    wrapProgram $out/bin/run_kselftest.sh \
      --prefix PATH : "${lib.makeBinPath deps}"
  '';
}
