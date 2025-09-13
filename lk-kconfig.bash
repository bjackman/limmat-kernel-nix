AVAIL_FRAGS=$(find "$LK_KCONFIG_FRAGMENTS_DIR/"* -printf '%f ')
FRAG_NAMES="base vm-boot"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Simple wrapper for Kconfig setup with some canned configs. It wraps
merge_config.sh and is intended to then add the feature of raising a hard error
if configs that are supposed to be enabled didn't, due to dependencies. But I
got bored before implementing that bit.

!!! This will overwrite your .config !!!

Options:
    -f, --frags FRAGS    Space-separated list of kconfig fragments to merge.
                         Available fragments are: $AVAIL_FRAGS
                         You can view their contents in $LK_KCONFIG_FRAGMENTS_DIR
                         Default: $FRAG_NAMES
    -e, --enable CONFIG  Space-separated list of extra configs to enable.
                         You can omit the CONFIG_ prefix.
    -h, --help           Display this help message and exit.

EOF
}

PARSED_ARGUMENTS=$(getopt -o e:f:h --long enable:,frags:,help -- "$@")

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments." >&2
    usage
    exit 1
fi
eval set -- "$PARSED_ARGUMENTS"

ENABLE=

while true; do
    case "$1" in
        -e|--enable)
            ENABLE="$2"
            shift 2
            ;;
        -f|--frags)
            FRAG_NAMES="$2"
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

# Convert from a list of fragment names to a list of paths
FRAGS=
for frag in $FRAG_NAMES; do
    new_frag="$LK_KCONFIG_FRAGMENTS_DIR/$frag"
    if [[ ! -e "$new_frag" ]]; then
        echo "No fragment $frag in $LK_KCONFIG_FRAGMENTS_DIR"
        exit 1
    fi
    FRAGS="$FRAGS $new_frag"
done

# Set up an initial .config and include the --enable options.
echo > .config
if [[ -n "$ENABLE" ]]; then
    echo "$ENABLE" | xargs -n 1 printf -- "--enable %s " | xargs scripts/config
fi

# -s means strict mode. This will raise an error if any of the config fragments
# (including .config, which we just created), directly override each other. But
# that doesn't take dependencies into account; if the final config doesn't match
# someting you requested then it just spits out an error and succeeds anyway.
#
# -n means to do something like "make oldnoconfig" instead of "olddefconfig" -
# i.e. it fills in the gaps with =n isntead of the default setting. This is a
# kinda opinionated option for this script to set, maybe it should be optional.
# shellcheck disable=SC2086
scripts/kconfig/merge_config.sh -s -n $FRAGS