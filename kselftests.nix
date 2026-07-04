# Builds kselftests from a given kernel source. Currently this only actually
# does the mm ones. The kselftest build is a big mess so more work is needed for
# each set of targets we wanna build.
{
  pkgs,
  lib,
  multiStdenv,
  fetchpatch,
  stdenv,

  # Explicit args.
  kernelSrc,
}:
let
  isX86_64 = stdenv.hostPlatform.system == "x86_64-linux";
  buildStdenv = if isX86_64 then multiStdenv else stdenv;

  # On 32-bit most stuff doesn't compile. On x86_64 I can build this subset of
  # kselftests. Assume that that will work on other systems too, although they
  # probably don't really.
  # TODO build the rest too
  kselftestsTargets =
    if stdenv.hostPlatform.system == "i686-linux" then
      [ "x86" ]
    else if isX86_64 then
      [
        "kvm"
        "mm"
        "x86"
      ]
    else
      [
        "kvm"
        "mm"
      ];
  targetsString = lib.concatStringsSep " " kselftestsTargets;

  # The x86 selftests are the only ones with special libc needs (see preBuild).
  buildsX86 = lib.elem "x86" kselftestsTargets;
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
    bash # so `patchShebangs --host` can find the target bash
  ];

  ARCH = stdenv.hostPlatform.linuxArch;
  CROSS_COMPILE = stdenv.cc.targetPrefix;

  # Cross builds only: put the _build_ platform compiler (e.g. the x86 compiler
  # when building on x86_64 for an arm64 target) on PATH, where it's found by
  # kbuild's default HOSTCC for host tools (fixdep, conf). We must NOT do this
  # for a native build: stdenv already provides a plain `gcc`, and adding a
  # second, non-multilib one here shadows multiStdenv's multilib gcc on x86_64,
  # silently dropping the 32-bit x86 selftests (gcc -m32 stops working).
  depsBuildBuild = lib.optionals (stdenv.buildPlatform.system != stdenv.hostPlatform.system) [
    pkgs.buildPackages.stdenv.cc
  ];
  enableParallelBuilding = true;
  postPatch = ''
    patchShebangs scripts
  '';
  # Need to set -j explicitly because it doesn't go into the $makeFlags until
  # buildPhase.
  configurePhase = ''
    make -j$NIX_BUILD_CORES defconfig
    scripts/config -e GUP_TEST
    make -j$NIX_BUILD_CORES olddefconfig
    grep GUP_TEST .config
  '';
  # The x86 selftests build 32-bit binaries and a couple of statically-linked
  # ones, so they need glibc variants that stdenv doesn't put on the link path
  # by default. Inject them for the x86 target only; kvm/mm need none of this.
  # NIX_LDFLAGS feeds the ld wrapper, LIBRARY_PATH feeds gcc.
  preBuild = ''
    make -j$NIX_BUILD_CORES headers
  ''
  + lib.optionalString buildsX86 (
    if isX86_64 then
      # Multilib: 32-bit shared glibc for the _32 tests, plus static archives
      # for both ABIs (check_initial_reg_state links -static).
      ''
        export NIX_LDFLAGS="-L${pkgs.glibc_multi.out}/lib/32 -L${pkgs.glibc_multi.static}/lib -L${pkgs.glibc_multi.static}/lib64 $NIX_LDFLAGS"
        export LIBRARY_PATH="${pkgs.glibc_multi.out}/lib/32:${pkgs.glibc_multi.static}/lib:${pkgs.glibc_multi.static}/lib64:$LIBRARY_PATH"
      ''
    else
      # i686 is already 32-bit natively, so it only needs the static glibc.
      ''
        export NIX_LDFLAGS="-L${pkgs.glibc.static}/lib $NIX_LDFLAGS"
        export LIBRARY_PATH="${pkgs.glibc.static}/lib:$LIBRARY_PATH"
      ''
  )
  + ''
    # Need to set this in shell code, there's no way to pass flags with spaces
    # otherwise lmao i don fuken no m8 wo'eva
    makeFlagsArray+=("TARGETS=${targetsString}")
    # HACK: -I../ works around
    # https://lore.kernel.org/all/DFHI984SEFV3.2JL88CLHNT2SO@google.com/
    makeFlagsArray+=("EXTRA_CFLAGS=-Wno-error=unused-result -fomit-frame-pointer -I../")
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
      # We already did patchShebangs on the build scripts but we need a separate
      # call for the scripts that run on the target (which will point to
      # different interpreters).
      patchShebangs --host $out/bin
      wrapProgram $out/bin/run_kselftest.sh \
        --prefix PATH : "${lib.makeBinPath deps}"
    '';
}
