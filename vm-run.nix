# This defines a script that runs a minimal NixOS VM with the kernel bzImage you
# pass as an argument. Use vm-kconfig to configure the kernel so that it's
# compatible with this hypervisor.
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
  name = "limmat-kernel-vm-run";
  runtimeInputs = [
    nixosRunner
    pkgs.getopt
  ];
  text = ''
    KERNEL_PATH="arch/x86/boot/bzImage"

    usage() {
        cat <<EOF
    Usage: $(basename "$0") [OPTIONS]

    Options:
      -k, --kernel PATH   Specify the path to the kernel image.
                          Default: $KERNEL_PATH
      -h, --help          Display this help message and exit.

    EOF
    }


    PARSED_ARGUMENTS=$(getopt -o k:h --long kernel:,help -- "$@")
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
      echo "Error: Failed to parse arguments." >&2
      usage
      exit 1
    fi
    eval set -- "$PARSED_ARGUMENTS"

    while true; do
        case "$1" in
            -k|--kernel)
              KERNEL_PATH="$2"
              shift 2
              ;;
            -h|--help)
              usage
              exit 0
              ;;
            --)
              shift
              break
              ;;
            *)
              echo "Unexpected argument, script bug? $1" >&2
              exit 1
              ;;
        esac
    done

    export NIXPKGS_QEMU_KERNEL_${hostName}="$KERNEL_PATH"
    ${nixosRunner}/bin/run-${hostName}-vm "$@"
  '';
}
