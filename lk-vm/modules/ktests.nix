# This module defines the stuff for running tests automatically via systemd,
# it is coupled to lk-vm.sh.
{
  pkgs,
  crossPkgs ? null,
  ...
}:
let
  ktestsOutputDir = "/mnt/ktests-output";
in
{
  virtualisation.vmVariant = {
    virtualisation = {
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

      status=0
      ${if crossPkgs != null then crossPkgs.ktests else pkgs.ktests}/bin/ktests \
        --junit-xml ${ktestsOutputDir}/junit.xml --log-dir ${ktestsOutputDir} \
        "''${args[@]}" || status=$?

      echo "$status" > ${ktestsOutputDir}/exit_code
      sync
      systemctl poweroff
    '';
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
    };
  };
}
