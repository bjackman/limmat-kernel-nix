{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    tmux
    binutils
    bpftrace
    perf
  ];
  virtualisation.vmVariant.virtualisation = {
    memorySize = 16 * 1024;
  };
}
