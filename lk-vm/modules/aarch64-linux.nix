{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    # Hack until we have SSH-vsock support or something
    tmux
    # KVM selftests shell out to addr2line on failure, which is quite handy.
    binutils
    bpftrace
    perf
  ];
  virtualisation.vmVariant.virtualisation = {
    memorySize = 16 * 1024;
  };
}
