# This defines a script that runs a minimal NixOS VM with the kernel bzImage you
# pass as an argument. Use lk-kconfig to configure the kernel so that it's
# compatible with this hypervisor.
{
  pkgs,
  stdenv,
  lib,
  self,
}:
let
  hostPkgs = pkgs;
  # Config to run on the host's native architecture (default)
  hostConfig = self.inputs.nixpkgs.lib.nixosSystem {
    system = stdenv.hostPlatform.system;
    modules = [
      ./modules/base.nix
      ./modules/${stdenv.hostPlatform.system}.nix
      { _module.args = { inherit self; }; }
    ];
  };
  # Config to run on 32-bit x86
  i686Config = self.inputs.nixpkgs.lib.nixosSystem {
    system = "i686-linux";
    modules = [
      ./modules/base.nix
      ./modules/i686-linux.nix
      { _module.args = { inherit self; }; }
    ];
  };
  # Takes the result of a nixosSystem call and produces the executable.
  mkPkg =
    config:
    let
      # nixosRunner is the "official" entry point for running NixOS as a QEMU guest,
      # we'll wrap this into a custom runner that supports overriding the kernel etc
      # at runtime.
      nixosRunner = config.config.system.build.vm;
    in
    pkgs.writeShellApplication {
      name = "lk-vm";
      runtimeInputs = [
        nixosRunner
        pkgs.getopt
      ];
      runtimeEnv.HOSTNAME = config.config.networking.hostName;
      text = builtins.readFile ./lk-vm.sh;
    };
in
# Main output is the result built for the host platform i.e. probably
# x86_64-linux.
(mkPkg hostConfig)
// {
  # Also hang the configs on the result as with passthru so they can be
  # inspected with nix eval etc.
  inherit hostConfig i686Config;
  # And then this version provides the 32-bit version if needed.
  # Obviously it would be preferable and totally possible to just have the
  # main executable have a --arch flag or whatever. But, that would make it
  # depend on the 32-bit system, which is not cached by NixOS, so basically
  # you'd have to compile a 32-bit system in order to use the 64-bit system.
  i686 = mkPkg i686Config;
}
