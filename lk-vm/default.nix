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
  hostnameFor =
    targetSystem:
    if targetSystem == "x86_64-linux" then
      "testvm_x86_64"
    else if targetSystem == "i686-linux" then
      "testvm_i686"
    else if targetSystem == "aarch64-linux" then
      "testvm_aarch64"
    else
      "testvm_unknown";

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
      isCross = targetSystem == "aarch64-linux" && stdenv.hostPlatform.system != "aarch64-linux";
      crossPkgs = if isCross then makeCrossPkgs targetSystem else null;
      targetPkgs =
        if targetSystem == stdenv.hostPlatform.system then
          pkgs
        else if targetSystem == "i686-linux" then
          i686Pkgs
        else
          null;
    in
    self.inputs.nixpkgs.lib.nixosSystem (
      if targetPkgs != null && !isCross then {
        pkgs = targetPkgs;
        modules = [
          ./modules/base.nix
          ./modules/${targetSystem}.nix
          {
            networking.hostName = hostnameFor targetSystem;
            _module.args = {
              inherit self hostPkgs crossPkgs;
            };
          }
        ];
      } else {
        # The system of the NixOS config is the TARGET system (so it is native to target)
        system = targetSystem;
        modules = [
          ./modules/base.nix
          ./modules/${targetSystem}.nix
          {
            nixpkgs.hostPlatform = targetSystem;
            networking.hostName = hostnameFor targetSystem;
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
  i686Config =
    if stdenv.hostPlatform.system == "i686-linux" then
      hostConfig
    else
      makeNixosConfig "i686-linux";

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

  lk-vm-multi = pkgs.writeShellApplication {
    name = "lk-vm";
    runtimeInputs = [
      hostConfig.config.system.build.vm
      aarch64Config.config.system.build.vm
      pkgs.getopt
    ];
    text = builtins.readFile ./lk-vm.sh;
  };
in
lk-vm-multi // {
  inherit hostConfig i686Config aarch64Config;
  x86_64 = mkPkg hostConfig;
  i686 = mkPkg i686Config;
  aarch64 = mkPkg aarch64Config;
}
