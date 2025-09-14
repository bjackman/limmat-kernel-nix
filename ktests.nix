{
  pkgs,
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

  # Helper function to create a vmtest for a specific test type
  mkVmtest =
    testType:
    mkTest (writeShellApplication {
      name = "vmtests-${testType}";
      runtimeInputs = [
        kselftests
      ]
      ++
        # run_vmtests.sh deps:
        (with pkgs; [
          bash
          gawk
        ]);
      text = ''
        cd ${kselftests}/bin/mm
        ./run_vmtests.sh -t ${testType}
      '';
    });

  tests = {
    # run_vmtests.sh is the wrapper script for the mm selftests. You can run the
    # whole thing via kselftests' crappy test runner but lots of the tests are
    # broken/flaky so you really only wanna run a subset. To do that via
    # kselftest you have to set KSELFTEST_RUN_VMTESTS_SH_ARGS but then you can't
    # set the -t arg to a string containing spaces. Easiest thing to do here is
    # just split it up into separate tests and always run a single sub-suite.
    # This is kinda wasteful because it means we run the setup/teardown more
    # often than necessary.
    # Note this is an incomplete list of the tests.
    vmtests = {
      mmap = mkVmtest "mmap";
      # TODO: This fails because mkstemp()/unlink() run into a read-only
      # filesystem.
      gup_test = mkVmtest "gup_test";
      # TODO: This fails because /proc/sys/vm/compact_unevictable_allowed is
      # missing.
      compaction = mkVmtest "compaction";
      # TODO: This needs CONFIG_TEST_VMALLOC=m in the kernel.
      vmalloc = mkVmtest "vmalloc";
      cow = mkVmtest "cow";
      # TODO: This fails because of numa_available missing.
      migration = mkVmtest "migration";
      # TODO: This fails because of "You need to compile page_frag_test module"
      # There seems to be a foible of run_vmtests.sh where it returns an error
      # when all tests are skipped.
      page_frag = mkVmtest "page_frag";
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
