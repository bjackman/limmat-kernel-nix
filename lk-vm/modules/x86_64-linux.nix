{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Hack until we have SSH-vsock support or something
    tmux
    # # Hack to make it easier to run kselftests that were built outside
    # # of Nix. KVM selftests shell out to addr2line on failure which is
    # # quite handy.
    binutils
    bpftrace
    perf
  ];
  # This BIOS doesn't mess up the terminal and is apparently faster.
  virtualisation.vmVariant.virtualisation.qemu.options = [
    "-bios"
    "qboot.rom"
  ];
  boot.kernelParams = [
    # Suggested by the error message of mm hugetlb selftests:
    "hugepagesz=1G"
    "hugepages=4"
  ];
}
