{
  pkgs,
  writeShellApplication,
  writeText,
  makeWrapper,
  runCommand,
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
      ++ (with pkgs; [
        # run_vmtests.sh deps:
        bash
        gawk
        # General stuff for all the scripts (too hard to track all
        # dependencies)
        killall
        mount
        umount
        procps
      ]);
      text = ''
        cd ${kselftests}/bin/mm
        ./run_vmtests.sh -t ${testType}
      '';
    });

  testConfig = {
    bad_tags = [
      # Doesn't work in the vm provided by lk-vm (with the kconfig provided by
      # `lk-kconfig -f "base vm-boot kselftests`).
      "lk-broken"
      # Too slow for me to want to run it on every commit. Not defined
      # precisely.
      "slow"
      # I've seen it fail and I didn't think it was my fault.
      "flaky"
    ];
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
      gup_test = (mkVmtest "gup_test") // {
        tags = [ "lk-broken" ];
      };
      compaction = mkVmtest "compaction";
      # TODO: This needs CONFIG_TEST_VMALLOC=m in the kernel.
      vmalloc = mkVmtest "vmalloc" // {
        tags = [ "lk-broken" ];
      };
      cow = mkVmtest "cow";
      migration = mkVmtest "migration";
      # TODO: This fails because of "You need to compile page_frag_test module"
      # There seems to be a foible of run_vmtests.sh where it returns an error
      # when all tests are skipped.
      page_frag = mkVmtest "page_frag" // {
        tags = [ "lk-broken" ];
      };
      thp = mkVmtest "thp" // {
        # TODO: There is a bug in split_huge_page_test, the ksft_set_plan() call
        # is broken under my configuratoin leading to:
        # Planned tests != run tests (62 != 10)
        tags = [ "lk-broken" ];
      };
      hugetlb = mkVmtest "hugetlb" // {
        # Broken during 6.18 merge window
        # https://lore.kernel.org/all/20250926033255.10930-1-kartikey406@gmail.com/T/#u
        tags = [
          "slow"
          "lk-broken"
        ];
      };
    };
    # parse-kselftest-list will generate the actual list of kselftests, but also
    # here we add tags and stuff for the ones we know about. This gets merged into
    # the overal config below.
    kselftests = {
      # Replaced by the explicit vmtests configuration above.
      # Note this is also affected by the bug with .sh being in the name.
      mm.run_vmtests_sh.tags = [ "lk-broken" ];
      kvm = {
        dirty_log_test.tags = [ "slow" ]; # It's not THAT slow
        set_memory_region_test.tags = [ "slow" ]; # It's not THAT slow
        dirty_log_perf_test.tags = [ "slow" ];
        demand_paging_test.tags = [ "slow" ];
        access_tracking_perf_test.tags = [ "slow" ];
        hardware_disable_test.tags = [ "slow" ];
        kvm_page_table_test.tags = [ "slow" ];
        memslot_modification_stress_test.tags = [ "slow" ];
        memslot_perf_test.tags = [ "slow" ];
        pre_fault_memory_test.tags = [ "slow" ];
        coalesced_io_test.tags = [ "slow" ];
        xapic_state_test.tags = [ "slow" ];
        # This test runs a guest with 128GiB of RAM, it's not gonna work in our
        # puny little VM.
        mmu_stress_test.tags = [
          "slow"
          "lk-broken"
        ];
        # Confirmed by seanjc to be flaky
        vmx_preemption_timer_test.tags = [ "flaky" ];
        # Fails with something that looks like a flaky assertion
        kvm_clock_test.tags = [ "flaky" ];
        # Several TSC-related tests are generally quite flaky.
        tsc_msrs_test.tags = [ "flaky" ];
        vmx_tsc_adjust_test.tags = [ "flaky" ];
        # Based on prodkernel experience I think this is actually also flaky, I
        # have never waited for it to finish upstream (note it does nothing when
        # only one CPU though).
        rseq_test.tags = [ "slow" ];
        # x86/fix_hypercall_test.c:75: ret == (uint64_t)-14
        fix_hypercall_test.tags = [ "lk-broken" ];
        # Failed:
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/19393418421/job/55490088190
        # Passed:
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/19392874394/job/55488849774
        msrs_test = [ "flaky" ];
        # Failed:
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/19392874394/job/55488849774
        # Passed:
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/19393418421/job/55490088190
        nx_huge_pages_test_sh.tags = [ "flaky" ];
        vmx_apic_access_test.tags = [ "flaky" ];
        vmx_dirty_log_test.tags = [ "flaky" ];
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/19412387941
        system_counter_offset_test.tags = [ "flaky" ];
      };
    };
    # Experimental example to test vibe-coded Github Actions bullshit. Remove me.
    example = {
      fail = mkTest (writeShellApplication {
        name = "example-fail";
        text = ''
          echo hello world
          echo hello world
          echo hello world
          echo hello world
          echo hello world
          echo hello world
          echo oh nooes
          exit 1
        '';
      });
    };
  };

  # Convert the tests config to JSON and store in nix store
  testConfigJson =
    runCommand "tests-config.json"
      {
        nativeBuildInputs = [
          pkgs.jq
          test-runner
        ];
      }
      ''
        test-runner parse-kselftest-list ${kselftests}/bin/kselftest-list.txt > kselftests.json
        # Combine the JSON generated from the Nix above, with the one generated by
        # parse-kselftest-list, but put the latter under the kselftests key.
        jq --slurp '{ "kselftests": .[0] } * .[1]' \
          kselftests.json \
          ${writeText "tests.json" (builtins.toJSON testConfig)} \
          > $out
      '';
in
# Create the wrapper that provides the config to test-runner
stdenv.mkDerivation {
  pname = "ktests";
  version = "0.1.0";

  src = ./.;

  buildInputs = [ kselftests ];
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    # The parse-kselftest-list result will generate JSON that expects to find
    # run_kselftest.sh in the PATH.
    makeWrapper ${test-runner}/bin/test-runner $out/bin/ktests \
      --add-flags "--test-config ${testConfigJson}" \
      --prefix PATH : "${kselftests}/bin"
  '';

  passthru.config = testConfigJson;
}
