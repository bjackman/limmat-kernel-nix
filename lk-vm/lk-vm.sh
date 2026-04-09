
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -t, --tree TREE      Optional path to a kernel tree.
    -k, --kernel PATH    Specify the path to the kernel image. If you set
                        --tree, defaults to the x86 bzImage in that treee.
    --nixos-kernel       Use the kernel from nixpkgs. Incompatible with --tree
                         --and --kernel.
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
    --vsock-cid          CID to assign for the guest for vsock connection.
                        Default is 3 - this is a global resource so if you're
                        running multiple instances at once you'll get errors.
                        Disable this by setting -1.
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
VSOCK_CID=3
USE_NIXOS_KERNEL=false

declare -a LKVM_RUN
LKVM_OUTPUT_HOST=

PARSED_ARGUMENTS=$(
    getopt -o t:k:c:dq:s::o:bh \
    --long tree:,kernel:,cmdline:,qemu-args:,debug,ktests::,ktests-output:,shutdown,help,vsock-cid:,nixos-kernel -- "$@")

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
        --nixos-kernel)
            USE_NIXOS_KERNEL=true
            shift
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
            # Set up base ktests flags
            # shellcheck disable=SC2016 # LKVM_OUTPUT_DIR is expanded in the guest
            LKVM_RUN=(
                ktests --bail-on-failure
                --junit-xml '$LKVM_OUTPUT_DIR'/junit.xml
                --log-dir '$LKVM_OUTPUT_DIR'
            )
            # Add extra args if provided, otherwise add default of '*' to run
            # all tests.
            if [[ -n "$2" ]]; then
                # Split the args into an array. This lets us expand it into args
                # later without glob expansion happening.
                IFS=' ' read -r -a extra_args <<< "$2"
            else
                extra_args=('*')
            fi
            LKVM_RUN+=("${extra_args[@]}")
            shift 2
            ;;
        -o|--ktests-output)
            LKVM_OUTPUT_HOST="$2"
            shift 2
            ;;
        -b|--shutdown)
            SHUTDOWN=true
            shift
            ;;
        --vsock-cid)
            VSOCK_CID="$2"
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

if ! "$USE_NIXOS_KERNEL"; then
    if [[ -z "$KERNEL_PATH" && -n "$KERNEL_TREE" ]]; then
        KERNEL_PATH="$KERNEL_TREE"/arch/x86/boot/bzImage
    fi
    if [[ -z "$KERNEL_PATH" ]]; then
        echo "Must set --kernel, --tree, or --nixos-kernel."
        exit 1
    fi
fi

# note the name of the LKVM_OUTPUT_HOST variable is coupled with the
# virtualisation.sharedDirectories option in the NixOS config.
if ! "$KTESTS" && [[ -n "$LKVM_OUTPUT_HOST" ]]; then
    echo "--ktests-output requires --ktests"
    exit 1
fi
# This needs to be set even if we aren't using --ktests, otherwise QEMU's
# 9pfs setup fails and QEMU falls over.
if [[ -z "$LKVM_OUTPUT_HOST" ]]; then
    LKVM_OUTPUT_HOST=$(mktemp -d)
fi

# If --tree wasn't provided, create a dummy directory since the shared
# directory with the guest is mandatory.
if [[ -z "$KERNEL_TREE" ]]; then
    KERNEL_TREE=$(mktemp -d)
    trap 'rmdir $KERNEL_TREE' EXIT
fi

if "$KTESTS"; then
    CMDLINE="$CMDLINE systemd.unit=lkvm-run.service systemd.setenv=LKVM_RUN=\"${LKVM_RUN[*]}\""
elif "$SHUTDOWN"; then
    # I dunno why the systemd.unit= is needed here, possibly as NixOS bug,
    # based on the systemd manual I expect setting systemd.run should
    # automatically make that the boot target.
    run_cmdline='"/run/current-system/sw/bin/bash -c true"'
    CMDLINE="$CMDLINE systemd.unit=kernel-command-line.service systemd.run=$run_cmdline"
fi

if [[ "$VSOCK_CID" != -1 ]]; then
    QEMU_OPTS="$QEMU_OPTS -device vhost-vsock-pci,guest-cid=$VSOCK_CID"
fi

# This NixOS VM script only works with absolute paths.
# The variable it uses depend on the hostname defined in the guest
# configuration - those are passed to this script via the environment.
if [[ -n "$KERNEL_PATH" ]]; then
    declare "NIXPKGS_QEMU_KERNEL_${HOSTNAME}=$(realpath "$KERNEL_PATH")"
fi
KERNEL_TREE="$(realpath "$KERNEL_TREE")"
export "NIXPKGS_QEMU_KERNEL_${HOSTNAME}"
export KERNEL_TREE
export LKVM_OUTPUT_HOST
export QEMU_KERNEL_PARAMS="$CMDLINE"
export QEMU_OPTS

set +e
"run-$HOSTNAME-vm" "$@"
exit_code=$?
if "$KTESTS"; then
    echo "Ktests output: $LKVM_OUTPUT_HOST"
fi
exit "$exit_code"