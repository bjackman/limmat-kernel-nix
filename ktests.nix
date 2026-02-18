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
    # parse-kselftest-list will generate the actual list of kselftests, but also
    # here we add tags and stuff for the ones we know about. This gets merged into
    # the overal config below.
    # Note that the ksefltests package doesn't build all the tests (see
    # TARGETS=).
    kselftests = {
      # Note this is also affected by the bug with .sh being in the name.
      mm = {
        # TODO: This fails because mkstemp()/unlink() run into a read-only
        # filesystem.
        ksft_gup_test_sh.tags = [ "lk-broken" ];
        # TODO: There is a bug in split_huge_page_test, the ksft_set_plan() call
        # is broken under my configuratoin leading to:
        # Planned tests != run tests (62 != 10)
        ksft_thp_sh.tags = [ "lk-broken" ];
        # TODO: This needs CONFIG_TEST_VMALLOC=m in the kernel.
        ksft_vmalloc_sh.tags = [ "lk-broken" ];
        # Not sure what's wrong with these ones:
        ksft_hmm_sh.tags = [ "lk-broken" ];
        ksft_hugetlb_sh.tags = [ "lk-broken" ];
        ksft_hugevm_sh.tags = [ "lk-broken" ];
        ksft_madv_guard_sh.tags = [ "lk-broken" ];
        ksft_mremap_sh.tags = [ "lk-broken" ];
        ksft_vma_merge_sh.tags = [ "lk-broken" ];
      };
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
        nested_tsc_adjust_test.tags = [ "flaky" ];
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
        cpuid_test.tags = [ "flaky" ];
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/20547584624
        nested_exceptions_test.tags = [ "flaky" ];
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/20768491948/job/59639617699
        tsc_scaling_test.tags = [ "flaky" ];
      };
      x86 = {
        # It prints SKIP but returns an error.
        test_shadow_stack_64.tags = [ "lk-broken" ];
        # This one goes into an infinite loop but only in GHA:
        # https://github.com/bjackman/limmat-kernel-nix/actions/runs/20803287757/job/59752430820#step:8:32
        mov_ss_trap_32 = [ "lk-broken" ];
        mov_ss_trap_64 = [ "lk-broken" ];
      };
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
