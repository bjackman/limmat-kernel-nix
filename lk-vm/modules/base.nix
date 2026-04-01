{
  pkgs,
  config,
  lib,
  self,
  ...
}:
let
  ktestsOutputDir = "/mnt/ktests-output";
  # I/O port that will be used for the isa-debug-exit device. I don't know
  # how arbitrary this value is, I got it from Gemini who I suspect is
  # cargo-culting from https://os.phil-opp.com/testing/
  qemuExitPortHex = "0xf4";
in
{
  nixpkgs.overlays = [ self.overlays.guest ];
  networking.hostName = "testvm";
  virtualisation.vmVariant = {
    virtualisation = {
      graphics = false;
      qemu.options = [
        "-device"
        "isa-debug-exit,iobase=${qemuExitPortHex},iosize=0x04"
      ];
      # Tell the VM runner script that it should mount a directory on the
      # host, named in the environment variable, to /mnt/kernel. That
      # variable must point to a directory. This is coupled with the script
      # content below.
      sharedDirectories = {
        kernel-tree = {
          source = "$KERNEL_TREE";
          target = "/mnt/kernel";
        };
        ktests-output = {
          source = "$KTESTS_OUTPUT_HOST";
          target = ktestsOutputDir;
        };
      };
      # Attempt to ensure there's space left over in the rootfs (which
      # may be where /tmp is).
      diskSize = 2 * 1024; # Megabytes
      # This seems to speed up boot a bit, and also I'm finding some KVM
      # selftests hang the VM on a uniprocessor system.
      cores = 8;
    };

    # mm selftests are hard-coded to put stuff in /tmp which has very
    # little space on a NixOS VM, unless it's a tmpfs.
    boot.tmp.useTmpfs = true;
  };
  system.stateVersion = "25.05";
  services.getty.autologinUser = "root";
  boot.kernelParams = [
    "nokaslr"
    "earlyprintk=serial"
  ];
  # I really don't know what the log levels are but this is the lowest
  # one that shows WARNs.
  boot.consoleLogLevel = 5;
  # Tell stage-1 not to bother trying to load the virtio modules since
  # we're using a custom kernel, the user has to take care of building
  # those in. We need mkForce because qemu-guest.nix doesn't respect
  # boot.inirtd.includeDefaultModules.
  boot.initrd.kernelModules = lib.mkForce [ ];

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

  # Some mmtests fail if the system doesn't have swap. I don't wanna
  # configure proper swap but let's try zswap.
  # zramSwap.enable = true;

  # Disable all networking stuff. The goal here was to speed up boot, it
  # doesn't seem to have a measurable effect but at least it avoids
  # having annoying errors in the logs.
  networking = {
    dhcpcd.enable = false;
    firewall.enable = false;
    useNetworkd = false;
    networkmanager.enable = false;
  };
  services.resolved.enable = false;

  # Not sure what this is but it seems irrelevant to this usecase.
  # Disabling it avoids some log spam and also seems to shave a couple
  # of hundred milliseconds off boot. BUT it breaks interactive login so
  # leave it enabled.
  security.enableWrappers = true;

  # Don't bother storing logs to disk, that seems like it will just
  # occasionally lead to unnecessary slowdowns for log rotation and
  # stuff.
  services.journald.storage = "volatile";

  # Turns out this doesn't stop the initrd from faffing around with the
  # device mapper but I guess disabling it might save some time
  # somewhere.
  services.lvm.enable = false;

  services.openssh = {
    enable = true;
    settings = {
      PermitEmptyPasswords = "yes";
      PermitRootLogin = "yes";
    };
  };
  users.users.root.initialHashedPassword = "";
  security.pam.services.sshd.allowNullPassword = true;

  nix.settings.require-sigs = false;
  nix.enable = false;

  environment.systemPackages = with pkgs; [
    ktests
    kselftests
    # Other stuff is defined directly in the 64bit config, to avoid having
    # to compile for 32-bit runs.

    # Because blktests really needs modprobe to work, replace modprobe
    # with a version that looks in a special directory where the user can
    # build modules (documented in the README) that can be loaded at
    # runtime.
    (pkgs.writeShellScriptBin "modprobe" ''
      ${pkgs.kmod}/bin/modprobe -d /mnt/kernel/modules_install "$@"
    '')
    # (pkgs.kmod.overrideAttrs (oldAttrs: {
    #   name = "kmod-lk-vm";
    #   nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.makeWrapper ];
    #   postInstall = oldAttrs.postInstall  + ''
    #     makeWrapper $out/bin/kmod $out/bin/modprobe \
    #       --add-flags "-d /mnt/kernel/modules_install"
    #   '';
    # }))
  ];

  documentation.enable = false;
}
