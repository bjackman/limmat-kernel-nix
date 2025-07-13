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
  nixosConfig = nixosSystem {
    inherit system;
    modules = [
      {
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
in
nixosConfig.config.system.build.vm
