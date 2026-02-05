# This defines a script that runs a minimal NixOS VM with the kernel bzImage you
# pass as an argument. Use lk-kconfig to configure the kernel so that it's
# compatible with this hypervisor.
{
  pkgs,
  lib,
  # This is the function that you would use in a flake to define a NixOS
  # configuration. It is not actually a part of nixpkgs itself but one of the
  # nixpkgs flakes' `lib` outputs so it needs to be passed here explicitly.
  nixosSystem,
  # ktests package to install in the guest.
  ktests,
  # For manual poking around, also put kselftests itself in the PATH.
  kselftests,
}:
let
  hostName = "testvm";
  nixosConfig = nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    modules =
      let
        # I/O port that will be used for the isa-debug-exit device. I don't know
        # how arbitrary this value is, I got it from Gemini who I suspect is
        # cargo-culting from https://os.phil-opp.com/testing/
        qemuExitPortHex = "0xf4";
      in
      [
        rec {
          networking.hostName = hostName;
          virtualisation.vmVariant = {
            virtualisation = {
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
                ktests-output = {
                  source = "$KTESTS_OUTPUT_HOST";
                  target = "/mnt/ktests-output";
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
          environment.systemPackages = [
            ktests
            kselftests
            # Hack until we have SSH-vsock support or something
            pkgs.tmux
            # Hack to make it easier to run kselftests that were built outside
            # of Nix. KVM selftests shell out to addr2line on failure which is
            # quite handy.
            pkgs.binutils
          ];
          boot.kernelParams = [
            "nokaslr"
            "earlyprintk=serial"
            # Suggested by the error message of mm hugetlb selftests:
            "hugepagesz=1G"
            "hugepages=4"
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
            script =
              let
                ktestsOutputDir = virtualisation.vmVariant.virtualisation.sharedDirectories.ktests-output.target;
              in
              ''
                # Convert the KTESTS_ARGS to an array so it can be expanded
                # without glob expansion.
                IFS=' ' read -r -a args <<< "$KTESTS_ARGS"
                # Writing the value v to the isa-debug-exit port will cause QEMU to
                # immediately exit with the exit code `v << 1 | 1`.
                ${ktests}/bin/ktests \
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
          zramSwap.enable = true;

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
      -q, --qemu-args ARGS Args to append to QEMU cmdline. Single string.
                           e.g. for a Skylake VM: "-cpu Skylake-Server,+vmx"
      -d, --debug          Enable GDB stub in QEMU. Connect with "target
                           remote localhost:1234" in GDB. Also disable watchdogs
                           and softlockup detectors. This is basically just
                           shorthand for certain --qemu-args and --cmdline args.
      -s, --ktests [ARGS]  Run a tests then shutdown. QEMU exit code reflects
                           test result. Optional arg is shell-expanded into
                           arguments for the ktests tool.
                           Note that this is parsed by GNU getopt, you can't
                           parse the arg like "-s foo" it needs to be "-sfoo"
                           or "--ktests=foo".
      -p, --ktests-output PATH  Directory to dump ktests output into (junit.xml, 
                                log files). Requires --ktests.
      -b, --shutdown       Just boot and then immediately shut down again.
      -h, --help           Display this help message and exit.

    EOF
    }

    # note the name of the KERNEL_TREE variable is coupled with the
    # virtualisation.sharedDirectories option in the NixOS config.
    KERNEL_TREE=
    KERNEL_PATH=
    CMDLINE=
    QEMU_OPTS=
    KTESTS=false
    SHUTDOWN=false

    KTESTS_ARGS=("--bail-on-failure" "*")
    KTESTS_OUTPUT_HOST=

    PARSED_ARGUMENTS=$(
      getopt -o t:k:c:dq:s::o:bh \
        --long tree:,kernel:,cmdline:,qemu-args:,debug,ktests::,ktests-output:,shutdown,help -- "$@")

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
              QEMU_OPTS="$QEMU_OPTS -s -S"
              # Don't want any watchdogs or softlockup detectors since they will
              # fire when we set breakpoints.
              CMDLINE="$CMDLINE nowatchdog rcupdate.rcu_cpu_stall_suppress=1 tsc=nowatchdog"
              shift
              ;;
            -q|--qemu-args)
              QEMU_OPTS="$QEMU_OPTS $2"
              shift 2
              ;;
            -s|--ktests)
              KTESTS=true
              if [[ -n "$2" ]]; then
               # Split the args into an/tmp/limmat-output-RolnKx array. This lets us expand it into args
               # later without glob expansion happening.
                IFS=' ' read -r -a KTESTS_ARGS <<< "$2"
              fi
              shift 2
              ;;
            -o|--ktests-output)
              KTESTS_OUTPUT_HOST="$2"
              shift 2
              ;;
            -b|--shutdown)
              SHUTDOWN=true
              shift
              ;;
            -h|--help)
              usag/tmp/limmat-output-RolnKxe
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

    # note the name of the KTESTS_OUTPUT_HOST variable is coupled with the
    # virtualisation.sharedDirectories option in the NixOS config.
    if ! "$KTESTS" && [[ -n "$KTESTS_OUTPUT_HOST" ]]; then
      echo "--ktests-output requires --ktests"
      exit 1
    fi
    # This needs to be set even if we aren't using --ktests, otherwise QEMU's
    # 9pfs setup fails and QEMU falls over.
    if [[ -z "$KTESTS_OUTPUT_HOST" ]]; then
      KTESTS_OUTPUT_HOST=$(mktemp -d)
    fi

    # If --tree wasn't provided, create a dummy directory since the shared
    # directory with the guest is mandatory.
    if [[ -z "$KERNEL_TREE" ]]; then
      KERNEL_TREE=$(mktemp -d)
      trap 'rmdir $KERNEL_TREE' EXIT
    fi

    if "$KTESTS"; then
      CMDLINE="$CMDLINE systemd.unit=ktests.service systemd.setenv=KTESTS_ARGS=\"''${KTESTS_ARGS[*]}\""
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
    export KTESTS_OUTPUT_HOST
    export QEMU_KERNEL_PARAMS="$CMDLINE"
    export QEMU_OPTS

    set +e
    ${nixosRunner}/bin/run-${hostName}-vm "$@"
    exit_code=$?
    if "$KTESTS"; then
      echo "Ktests output: $KTESTS_OUTPUT_HOST"
    fi
    exit "$exit_code"
  '';
  passthru = { inherit nixosConfig; };
}
