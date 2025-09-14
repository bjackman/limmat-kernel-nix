{
  writeShellApplication,
  writeText,
  makeWrapper,
  stdenv,
  lib,

  # Dependency packages
  kselftests,
  test-runner,
}:
let
  # Helper function to create a test definition from a derivation
  mkTest = drv: {
    __is_test = true;
    command = [ "${drv}/bin/${drv.pname or drv.name}" ];
  };

  tests = {
    # run_vmtests.sh is the wrapper script for the mm selftests. You can run the
    # whole thing via kselftests' crappy test runner but lots of the tests are
    # broken/flaky so you really only wanna run a subset. To do that via
    # kselftest you have to set KSELFTEST_RUN_VMTESTS_SH_ARGS but then you can't
    # set the -t arg to a string containing spaces. Easiest thing to do here is
    # just split it up into separate tests and always run a single sub-suite.
    # This is kinda wasteful because it means we run the setup/teardown more
    # often than necessary.
    vmtests = {
      mmap = mkTest (writeShellApplication {
        name = "vmtests-mmap";
        runtimeInputs = [ kselftests ];
        text = ''
          # run_vmtests.sh assumes it's being run from the mm directory.
          cd ${kselftests}/bin/mm
          ./run_vmtests.sh -t mmap
        '';
      });
    };
  };

  # Convert the tests config to JSON and store in nix store
  testsConfig = writeText "tests-config.json" (builtins.toJSON tests);

  # Create the wrapper that provides the config to test-runner
  ktests = stdenv.mkDerivation {
    pname = "ktests";
    version = "0.1.0";

    src = ./.;

    nativeBuildInputs = [ makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin
      makeWrapper ${test-runner}/bin/test-runner $out/bin/ktests \
        --add-flags "--test-config ${testsConfig}"
    '';
  };
in
ktests
