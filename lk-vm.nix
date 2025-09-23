# This defines a script that runs a minimal NixOS VM with the kernel bzImage you
# pass as an argument. Use lk-kconfig to configure the kernel so that it's
# compatible with this hypervisor.
{
  pkgs,
  lib,
  system,
  # This is the function that you would use in a flake to define a NixOS
  # configuration. It is not actually a part of nixpkgs itself but one of the
  # nixpkgs flakes' `lib` outputs so it needs to be passed here explicitly.
  nixosSystem,
  # ktests package to install in the guest.
  ktests,
}:
let
  hostName = "testvm";
  nixosConfig = nixosSystem {
    inherit system;
    modules =
      let
        # I/O port that will be used for the isa-debug-exit device. I don't know
        # how arbitrary this value is, I got it from Gemini who I suspect is
        # cargo-culting from https://os.phil-opp.com/testing/
        qemuExitPortHex = "0xf4";
      in
      [
        {
          networking.hostName = hostName;
          virtualisation.vmVariant.virtualisation = {
            graphics = false;
            # This BIOS doesn't mess up the terminal and is apparently faster.
            qemu.options = [
              "-bios"
              "qboot.rom"
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
            };
            memorySize = 4 * 1024; # Megabytes
          };
          system.stateVersion = "25.05";
          services.getty.autologinUser = "root";
          environment.systemPackages = [ ktests ];
          boot.kernelParams = [
            "nokaslr"
            "earlyprintk=serial"
            "debug"
            "loglevel=7"
            # There seems to be a bug in the kernel or QEMU which leads to boot
            # failing when I'm running lots of QEMU instances at once. Disabling
            # this seems to work around it...
            "noapic"
          ];
          # Tell stage-1 not to bother trying to load the virtio modules since
          # we're using a custom kernel, the user has to take care of building
          # those in. We need mkForce because qemu-guest.nix doesn't respect
          # boot.inirtd.includeDefaultModules.
          boot.initrd.kernelModules = lib.mkForce [ ];

          # As an easy way to be able to run it from the kernel cmdline, just
          # encode ktests into a systemd service. You can then run it with
          # systemd.unit=ktests.service.
          systemd.services.ktests = {
            path = [ pkgs.which ];
            script = ''
              # Writing the value v to the isa-debug-exit port will cause QEMU to
              # immediately exit with the exit code `v << 1 | 1`.
              ${ktests}/bin/ktests $KTESTS_ARGS \
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
          zramSwap.enable = true;

          # Disable all networking stuff. The goal here was to speed up boot, it
          # doesn't seem to have a measurable effect but at least it avoids
          # having annoying errors in the logs.
          networking = {
            dhcpcd.enable = false;
            firewall.enable = false;
            useNetworkd = true;
          };
          services.resolved.enable = false;
          systemd.network = {
            enable = true;
            networks = { };
          };

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
        }
      ];
  };
  # This is the "official" entry point for running NixOS as a QEMU guest, we'll
  # wrap this.
  nixosRunner = nixosConfig.config.system.build.vm;
in
pkgs.writeShellApplication {
  name = "lk-vm";
  runtimeInputs = [
    nixosRunner
    pkgs.getopt
  ];
  text = ''
    usage() {
        cat <<EOF
    Usage: $(basename "$0") [OPTIONS]

    Options:
      -t, --tree TREE      Optional path to a kernel tree.
      -k, --kernel PATH    Specify the path to the kernel image. If you set
                           --tree, defaults to the x86 bzImage in that treee.
      -c, --cmdline ARGS   Args to append to kernel cmdline. Single string.
      -d, --debug          Enable GDB stub in QEMU. Connect with "target
                           remote localhost:1234" in GDB.
      -s, --ktests [ARGS]  Run a tests then shutdown. QEMU exit code reflects
                           test result. Optional arg is shell-expanded into
                           arguments for the ktests tool.
                           Note that this is parsed by GNU getopt, you can't
                           parse the arg like "-s foo" it needs to be "-sfoo"
                           or "--ktests=foo".
      -b, --shutdown       Just boot and then immediately shut down again.
      -h, --help           Display this help message and exit.

    EOF
    }

    # Note the name of the KERNEL_TREE variable is coupled with the
    # virtualisation.sharedDirectories option in the NixOS config.
    KERNEL_TREE=
    KERNEL_PATH=
    CMDLINE=
    QEMU_OPTS=
    KTESTS=false
    SHUTDOWN=false

    KTESTS_ARGS="--skip-tag lk-broken vmtests.*"

    PARSED_ARGUMENTS=$(
      getopt -o t:k:c:ds::bh \
        --long tree:,kernel:,cmdline:,debug,ktests::,shutdown,help -- "$@")

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
            -t|--tree)
              KERNEL_TREE="$2"
              shift 2
              ;;
            -c|--cmdline)
              CMDLINE="$2"
              shift 2
              ;;
            -d|--debug)
              QEMU_OPTS="-s -S"
              shift
              ;;
            -s|--ktests)
              KTESTS=true
              if [[ -n "$2" ]]; then
                KTESTS_ARGS="$2"
              fi
              shift 2
              ;;
            -b|--shutdown)
              SHUTDOWN=true
              shift
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

    if [[ -z "$KERNEL_PATH" && -n "$KERNEL_TREE" ]]; then
      KERNEL_PATH="$KERNEL_TREE"/arch/x86/boot/bzImage
    fi
    if [[ -z "$KERNEL_PATH" ]]; then
      echo "Must set --kernel or --tree."
      exit 1
    fi

    # If --tree wasn't provided, create a dummy directory since the shared
    # directory with the guest is mandatory.
    if [[ -z "$KERNEL_TREE" ]]; then
      KERNEL_TREE=$(mktemp -d)
      trap 'rmdir $KERNEL_TREE' EXIT
    fi

    if "$KTESTS"; then
      CMDLINE="$CMDLINE systemd.unit=ktests.service systemd.setenv=KTESTS_ARGS=\"$KTESTS_ARGS\""
    elif "$SHUTDOWN"; then
      # I dunno why the systemd.unit= is needed here, possibly as NixOS bug,
      # based on the systemd manual I expect setting systemd.run should
      # automatically make that the boot target.
      run_cmdline='"/run/current-system/sw/bin/bash -c true"'
      CMDLINE="$CMDLINE systemd.unit=kernel-command-line.service systemd.run=$run_cmdline"
    fi

    # This NixOS VM script only works with absolute paths.
    NIXPKGS_QEMU_KERNEL_${hostName}="$(realpath "$KERNEL_PATH")"
    KERNEL_TREE="$(realpath "$KERNEL_TREE")"
    export NIXPKGS_QEMU_KERNEL_${hostName}
    export KERNEL_TREE
    export QEMU_KERNEL_PARAMS="$CMDLINE"
    export QEMU_OPTS
    ${nixosRunner}/bin/run-${hostName}-vm "$@"
  '';
}
