# Stupidly verbose wrapper for configuring kernel and checking configs are set.

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
    -b, --base NAME      Name of base config targets, space-separated. Default
                         is 'defconfig kvm_guest.config'.
    -e, --enable CONFIG  Config that must be enabled in final config.
                         Repeatable. You can omit the CONFIG_ prefix.
    -h, --help           Display this help message and exit.

EOF
}

PARSED_ARGUMENTS=$(getopt -o e:b:h --long enable:,base:,help -- "$@")

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments." >&2
    usage
    exit 1
fi
eval set -- "$PARSED_ARGUMENTS"

BASE_TARGETS="defconfig kvm_guest.config"

# OVERLAY_FS required for NixOS to boot.
REQUIRED_KCONFIGS=("OVERLAY_FS")

while true; do
    case "$1" in
        -e|--enable)
            REQUIRED_KCONFIGS+=("$2")
            shift 2
            ;;
        -b|--base)
            BASE_TARGETS="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unexpected argument, script bug? $1" >&2
            exit 1
            ;;
    esac
done

for target in $BASE_TARGETS; do
    make "$target"
done

# TODO: Don't hard code this shit
scripts/config -e GUP_TEST
scripts/config -e DEBUG_KERNEL -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT -e GDB_SCRIPTS

echo "${REQUIRED_KCONFIGS[@]}" | xargs -n 1 printf -- "--enable %s " | xargs scripts/config

make -j olddefconfig

errors=false
for conf in "${REQUIRED_KCONFIGS[@]}"; do
    if ! grep -q "$conf=y" .config; then
    echo "$conf not enabled in final config!"
    errors=true
    fi
done
if $errors; then
    exit 1
fi