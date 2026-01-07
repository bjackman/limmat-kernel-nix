AVAIL_FRAGS=$(find "$LK_KCONFIG_FRAGMENTS_DIR/" -type f -printf '%P ')
FRAG_NAMES="base vm-boot"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Simple wrapper for Kconfig setup with some canned configs. It wraps
merge_config.sh and then just adds the extra feature of checking whether you
actually set all the configs you meant to.

!!! This will overwrite your .config !!!

Options:
    -f, --frags FRAGS    Space-separated list of kconfig fragments to merge.
                         Available fragments are: $AVAIL_FRAGS
                         You can view their contents in $LK_KCONFIG_FRAGMENTS_DIR
                         You can pass a directory like kselftests to enable all
                         fragments in that directory.
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

# In case the user passses a -- and then extra args, fail.
if [ $# -ne 0 ]; then
    echo "Error: Unexpected arguments found: $*" >&2
    usage
    exit 1
fi

# Convert from a list of fragment names to a list of paths
set -x
FRAGS=
for frag in $FRAG_NAMES; do
    new_frag="$LK_KCONFIG_FRAGMENTS_DIR/$frag"
    if [[ ! -e "$new_frag" ]]; then
        echo "No fragment $frag in $LK_KCONFIG_FRAGMENTS_DIR"
        exit 1
    elif [[ -d "$new_frag" ]]; then
      # It's a directory, add all the subfiles to FRAGS.
      # This silly dance is suggested in https://www.shellcheck.net/wiki/SC2044
      while IFS= read -r -d '' dir_frag
      do
        FRAGS="$FRAGS $dir_frag"
      done < <(find "$new_frag" -type f -print0)
    else
      FRAGS="$FRAGS $new_frag"
    fi
done
set +x

# Set up an initial .config and include the --enable options. Save this so we
# can use it to check the config later.
TMPCONFIG=$(mktemp)
trap 'rm $TMPCONFIG' EXIT
if [[ -n "$ENABLE" ]]; then
    echo "$ENABLE" | xargs -n 1 printf -- "--enable %s " | xargs scripts/config --file "$TMPCONFIG"
fi
cp "$TMPCONFIG" .config

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

# Check configs that were requested to be enabled. This is just all nonempty
# lines that don't start with #.
enables_re='^[^#].*$'
# shellcheck disable=SC2086
enables_requested=$(cat "$TMPCONFIG" $FRAGS | grep "$enables_re" | sort | uniq)
enables_actual=$(grep "$enables_re" .config | sort | uniq)
missing_enables=$(comm -2 -3 <(echo "$enables_requested") <(echo "$enables_actual"))
if [[ -n "$missing_enables" ]]; then
    echo "Config settings missing from final config. Dependencies not handled? Typos? Missing lines:"
    echo "$missing_enables"
    exit 1
fi

# Now check configs that we wanted to be disabled. Note Kconfig is fucked up
# and "# CONFIG_FOO is not set" is a kinda up sort-of-comment where actually it
# can sometimes carry semantic meaning.
# First extract the specific configs that were explicitly requested to be
# disabled.
# shellcheck disable=SC2086
want_disabled_configs=$(cat "$TMPCONFIG" $FRAGS | sed -En "s/^# (CONFIG_[A-Z0-9_]+) is not set$/\1/p" | sort | uniq)
# Now get all the options that were configured (don't care about the actual that
# was set, don't care about "is not set" lines, just care about
# CONFIG_FOO=something lines).
enabled_configs=$(sed -En 's/^(CONFIG_[A-Z0-9_]+)=.*$/\1/p' .config | sort | uniq)
unexpected_configs=$(comm -1 -2 <(echo "$want_disabled_configs") <(echo "$enabled_configs"))
if [[ -n "$unexpected_configs" ]]; then
    echo "Configs appearing in the final config that were marked as 'is not set' in the fragments:"
    echo "$unexpected_configs"
    exit 1
fi