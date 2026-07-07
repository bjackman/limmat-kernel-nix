{ ... }:
{
  # QEMU depends on a library that doesn't compile for 32-bit so disable the
  # guest agent. (The host's QEMU package is already forced in base.nix.)
  virtualisation.vmVariant.virtualisation.qemu.guestAgent.enable = false;
}
