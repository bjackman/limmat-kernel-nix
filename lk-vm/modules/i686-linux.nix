{ pkgs, hostPkgs, ... }:
{
  virtualisation.vmVariant.virtualisation.qemu = {
    # QEMU depends on a library that doesn't compile for 32-bit so we
    # need to explicitly disable the guest agent and force the runner
    # to use the host's QEMU package
    guestAgent.enable = false;
    package = hostPkgs.qemu;
  };
  virtualisation.vmVariant.virtualisation.memorySize = 2046;
}
