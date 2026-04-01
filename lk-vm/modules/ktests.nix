# This module defines the stuff for running ktests automatically via systemd,
# it is coupled to the --ktests arg of lk-vm.sh.
{ pkgs, ... }:
let
  ktestsOutputDir = "/mnt/ktests-output";
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
        ktests-output = {
          source = "$KTESTS_OUTPUT_HOST";
          target = ktestsOutputDir;
        };
      };
    };

    # mm selftests are hard-coded to put stuff in /tmp which has very
    # little space on a NixOS VM, unless it's a tmpfs.
    boot.tmp.useTmpfs = true;
  };

  # As an easy way to be able to run it from the kernel cmdline, just
  # encode ktests into a systemd service. You can then run it with
  # systemd.unit=ktests.service.
  systemd.services.ktests = {
    script = ''
      # Convert the KTESTS_ARGS to an array so it can be expanded
      # without glob expansion.
      IFS=' ' read -r -a args <<< "$KTESTS_ARGS"
      # Writing the value v to the isa-debug-exit port will cause QEMU to
      # immediately exit with the exit code `v << 1 | 1`.
      ${pkgs.ktests}/bin/ktests \
        --junit-xml ${ktestsOutputDir}/junit.xml --log-dir ${ktestsOutputDir} \
        "''${args[@]}" \
        || ${pkgs.ioport}/bin/outb ${qemuExitPortHex} $(( $? - 1 ))
    '';
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
    };
    onSuccess = [ "poweroff.target" ];
  };
}
