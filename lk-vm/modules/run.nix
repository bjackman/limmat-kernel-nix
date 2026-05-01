# This module defines the stuff for running tests automatically via systemd,
# it is coupled to lk-vm.sh.
# It basically runs the command in the LKVM_RUN environment variable, passing
# LKVM_OUTPUT_DIR in the environment.
{ pkgs, ... }:
let
  outputDir = "/mnt/lkvm-output";
  # I/O port that will be used for the isa-debug-exit device. I don't know
  # how arbitrary this value is, I got it from Gemini who I suspect is
  # cargo-culting from https://os.phil-opp.com/testing/
  qemuExitPortHex = "0xf4";
in
{
  virtualisation.vmVariant = {
    virtualisation = {
      qemu.options = [
        "-device"
        "isa-debug-exit,iobase=${qemuExitPortHex},iosize=0x04"
      ];
      sharedDirectories = {
        output = {
          source = "$LKVM_OUTPUT_HOST";
          target = outputDir;
        };
      };
    };

    # mm selftests are hard-coded to put stuff in /tmp which has very
    # little space on a NixOS VM, unless it's a tmpfs.
    boot.tmp.useTmpfs = true;
  };

  # As an easy way to be able to run stuff from the kernel cmdline, define
  # a systemd service that runs commands provided by the LKVM_RUN env var.
  systemd.services.lkvm-run = {
    script = ''
      # Convert LKVM_RUN to an array so it can be expanded without glob
      # expansion.
      IFS=' ' read -r -a args <<< "$LKVM_RUN"
      # Writing the value v to the isa-debug-exit port will cause QEMU to
      # immediately exit with the exit code `v << 1 | 1`.
      "''${args[@]}" \
        || ${pkgs.ioport}/bin/outb ${qemuExitPortHex} $(( $? - 1 ))
    '';
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
    };
    environment.LKVM_OUTPUT_DIR = outputDir;
    onSuccess = [ "poweroff.target" ];
    path = [ pkgs.ktests ];
  };
}
