# This defines a script that runs a minimal NixOS VM with the kernel bzImage you
# pass as an argument. Use lk-kconfig to configure the kernel so that it's
# compatible with this hypervisor.
{
  pkgs,
  stdenv,
  lib,
  self,
  i686Pkgs,
}:
let
  hostPkgs = pkgs;
  makeCrossPkgs =
    targetSystem:
    import self.inputs.nixpkgs {
      localSystem = stdenv.hostPlatform.system;
      crossSystem = targetSystem;
      overlays = [ self.overlays.guest ];
    };

  # Helper to create NixOS config, optionally cross-compiling
  makeNixosConfig =
    targetSystem:
    let
      isCross = targetSystem != stdenv.hostPlatform.system;
      crossPkgs = if isCross then makeCrossPkgs targetSystem else null;
    in
    self.inputs.nixpkgs.lib.nixosSystem (
      if isCross then {
        # The system of the NixOS config is the TARGET system (so it is native to target)
        system = targetSystem;
        modules = [
          ./modules/base.nix
          ./modules/${targetSystem}.nix
          {
            nixpkgs.hostPlatform = targetSystem;
            _module.args = {
              inherit self hostPkgs crossPkgs;
            };
          }
        ];
      } else {
        inherit pkgs;
        modules = [
          ./modules/base.nix
          ./modules/${targetSystem}.nix
          {
            _module.args = {
              inherit self hostPkgs crossPkgs;
            };
          }
        ];
      }
    );

  # Config to run on the host's native architecture (default)
  hostConfig = makeNixosConfig stdenv.hostPlatform.system;

  # Config to run on ARM64
  aarch64Config =
    if stdenv.hostPlatform.system == "aarch64-linux" then
      hostConfig
    else
      makeNixosConfig "aarch64-linux";

  # Config to run on 32-bit x86
  i686Config = self.inputs.nixpkgs.lib.nixosSystem {
    pkgs = i686Pkgs;
    modules = [
      ./modules/base.nix
      ./modules/i686-linux.nix
      { _module.args = { inherit self hostPkgs; }; }
    ];
  };

  # Takes the result of a nixosSystem call and produces the executable.
  mkPkg =
    config:
    let
      nixosRunner = config.config.system.build.vm;
      targetSystem = config.config.nixpkgs.hostPlatform.system;
    in
    pkgs.writeShellApplication {
      name = "lk-vm";
      runtimeInputs = [
        nixosRunner
        pkgs.getopt
      ];
      runtimeEnv.HOSTNAME = config.config.networking.hostName;
      runtimeEnv.TARGET_SYSTEM = targetSystem;
      text = builtins.readFile ./lk-vm.sh;
    };
in
(mkPkg hostConfig)
// {
  inherit hostConfig i686Config aarch64Config;
  i686 = mkPkg i686Config;
  aarch64 = mkPkg aarch64Config;
}
