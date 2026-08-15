# This defines a script that runs a minimal NixOS VM with the kernel image you
# pass as an argument. Use lk-kconfig to configure the kernel so that it's
# compatible with this hypervisor.
#
# A guest for a non-host arch (e.g. arm64 on an x86_64 host) runs under the
# host's QEMU (TCG emulation). The guest OS is a *native* build for the target,
# so it comes from the binary cache rather than being cross-compiled or built
# under emulation. A consequence is that the guest's VM runner script is a
# target-arch executable, so `lk-vm --arch arm64` needs binfmt registered for
# the target on the host (boot.binfmt.emulatedSystems = [ "aarch64-linux" ]).
# The test packages that are built from sources no cache can know about (the
# flake's kernel input, this repo) we cross-compile instead of emulating; the
# rest are built natively so their dependencies substitute. See flake.nix,
# which instantiates all the package sets.
{
  pkgs,
  stdenv,
  lib,
  self,
  # Package sets, instantiated by the flake. guestPkgs is keyed by target
  # system; guestCrossPkgs is keyed by the subset of those we cross-compile a
  # few packages for.
  guestPkgs,
  guestCrossPkgs,
}:
let
  inherit (self.inputs.nixpkgs.lib) nixosSystem;
  hostPkgs = pkgs;
  hostSystem = stdenv.hostPlatform.system;

  # e.g. "aarch64-linux" -> "testvm_aarch64". Coupled with the arch handling in
  # lk-vm.sh, which dispatches to run-<hostname>-vm.
  hostnameFor = targetSystem: "testvm_" + lib.removeSuffix "-linux" targetSystem;

  # Test packages for the guest. These are the native ones, except that for a
  # guest of another arch we take the packages built from sources no cache can
  # know about from the cross set instead - building those is unavoidable, and
  # cross-compiling beats emulating.
  guestTestPkgs =
    targetSystem:
    let
      crossPkgs = guestCrossPkgs.${targetSystem} or null;
    in
    if targetSystem == hostSystem || crossPkgs == null then
      guestPkgs.${targetSystem}
    else
      guestPkgs.${targetSystem}.extend (final: prev: { inherit (crossPkgs) kselftests test-runner; });

  mkConfig =
    targetSystem:
    nixosSystem {
      pkgs = guestPkgs.${targetSystem};
      modules = [
        ./modules/base.nix
        ./modules/${targetSystem}.nix
        {
          networking.hostName = hostnameFor targetSystem;
          _module.args = {
            inherit self hostPkgs;
            testPkgs = guestTestPkgs targetSystem;
          };
        }
      ];
    };

  hostConfig = mkConfig hostSystem;
  i686Config = mkConfig "i686-linux";
  aarch64Config = mkConfig "aarch64-linux";

  # Build the lk-vm launcher wrapping one or more guest configs. lk-vm.sh
  # dispatches to run-<hostname>-vm based on --arch, so every guest we want to
  # be able to boot needs its runner on PATH. `default` is the target system
  # used when --arch isn't given.
  mkPkg =
    {
      default,
      configs,
    }:
    pkgs.writeShellApplication {
      name = "lk-vm";
      runtimeInputs = [ pkgs.getopt ] ++ map (c: c.config.system.build.vm) configs;
      runtimeEnv.TARGET_SYSTEM = default;
      text = builtins.readFile ./lk-vm.sh;
    };
in
# The default launcher covers the host arch plus arm64 (which emulates without a
# big local build). i686 is a separate output because NixOS doesn't cache it, so
# bundling it would mean compiling a whole 32-bit system just to get the rest.
(mkPkg {
  default = hostSystem;
  configs = [
    hostConfig
    aarch64Config
  ];
})
// {
  # Hang the configs on the result as passthru so they can be inspected with
  # nix eval etc.
  inherit hostConfig i686Config aarch64Config;
  x86_64 = mkPkg {
    default = "x86_64-linux";
    configs = [ hostConfig ];
  };
  i686 = mkPkg {
    default = "i686-linux";
    configs = [ i686Config ];
  };
  aarch64 = mkPkg {
    default = "aarch64-linux";
    configs = [ aarch64Config ];
  };
}
