{ pkgs, ... }:
{
  virtualisation.vmVariant.virtualisation.qemu = {
    # QEMU depends on a library that doesn't compile for 32-bit so we
    # need to explicitly disable the guest agent and force the runner
    # to use the host's QEMU package
    guestAgent.enable = false;
    package = hostPkgs.qemu;
  };
  # Disable ShellCheck so we don't have to compile GHC
  nixpkgs.overlays = [
    (final: prev: {
      writeShellApplication =
        args:
        prev.writeShellApplication (
          args
          // {
            checkPhase = "";
          }
        );
    })
  ];
}
