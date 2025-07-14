{
  pkgs,
  lib,
  system,
  # This is the function that you would use in a flake to define a NixOS
  # configuration. It is not actually a part of nixpkgs itself but one of the
  # nixpkgs flakes' `lib` outputs so it needs to be passed here explicitly.
  nixosSystem,
}:
let
  hostName = "testvm";
  nixosConfig = nixosSystem {
    inherit system;
    modules = [
      {
        networking.hostName = hostName;
        virtualisation.vmVariant.virtualisation = {
          graphics = false;
          # This BIOS doesn't mess up the terminal and is apparently faster.
          qemu.options = [
            "-bios"
            "qboot.rom"
          ];
        };
        system.stateVersion = "25.05";
        services.getty.autologinUser = "root";
      }
    ];
  };
  # This is the "official" entry point for running NixOS as a QEMU guest, we'll
  # wrap this.
  nixosRunner = nixosConfig.config.system.build.vm;
in
pkgs.writeShellApplication {
  name = "limmat-kernel-run-vm";
  runtimeInputs = [ nixosRunner ];
  text = ''
    set -eux

    export NIXPKGS_QEMU_KERNEL_${hostName}="$1"
    shift
    ${nixosRunner}/bin/run-${hostName}-vm "$@"
  '';
}
