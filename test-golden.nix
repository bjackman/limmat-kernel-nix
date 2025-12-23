{
  pkgs,
  lib,
  # The main package of this repository.
  limmat-kernel,
  # The Limmat configuration defined by this repository as a Nix attrset.
  limmatConfig,
  kernelSrc,
}:
let
  fakeKernelRepo = pkgs.runCommand "fake-kernel-repo" { } ''
    set -euo pipefail

    mkdir $out
    cd $out

    PATH=${pkgs.git}/bin:"$PATH"

    # Set a hard-coded date to try and make the commit hash
    # deterministic. Not certain this works.
    export GIT_AUTHOR_DATE="2000-01-01T00:00:00Z"
    export GIT_COMMITTER_DATE="2000-01-01T00:00:00Z"

    ${pkgs.rsync}/bin/rsync -a --chmod=u+w ${kernelSrc}/* .

    git init
    git config user.email chung.flunch@example.com
    git config user.name "Chungonius Flunchér XIII"
    git add .
    git commit -m "init fake repo to make limmat happy"

    # We'll run checkpatch which falls over if there isn't a vaguely realistic
    # commit at HEAD.
    echo "/* ok */" >> mm/page_alloc.c
    git commit --signoff -m "another commit to avoid DoSing checkpatch" mm/page_alloc.c
  '';
in
pkgs.writeShellApplication {
  name = "limmat-kernel-test-golden";
  runtimeInputs = [
    pkgs.gnutar
    pkgs.git
    pkgs.coreutils
    pkgs.rsync
    limmat-kernel
  ];
  passthru = { inherit fakeKernelRepo; };
  text = ''
    # For the benefit of Github, takes an optional single argument that tells it
    # where to put the limmat DB. This is a hack to allow exporting JUnit XML
    # data to the UI.
    LIMMAT_DB_PATH="$1"

    set -eux -o pipefail

    TMPDIR="$(mktemp -d)"
    if [[ -z "$LIMMAT_DB_PATH" ]]; then
      LIMMAT_DB_PATH="$TMPDIR"/limmat-db
    fi

    # Note this evaluates $PWD now so this will change back to the current
    # directory
    # shellcheck disable=SC2064
    trap "cd $PWD && rm -rf $TMPDIR" EXIT
    cd "$TMPDIR"

    # If we just have a Nix derivation that produces a kernel
    # repository then Limmat will fall over because the .git dir
    # has what Git describes as "dubious permissions". So instead
    # we do this silly dance to set up a golden tree in a
    # reproducible way: we build it in the nix store then copy it into a
    # directory that we own here.
    rsync -a --no-owner --chmod=u+w ${fakeKernelRepo} .
    cd ./"$(basename ${fakeKernelRepo})"

    # By default limmat logs to your home dir (dumb?).
    export LIMMAT_LOGFILE=$TMPDIR/limmat.log

    # Disable warning if loop always has exactly one iteration.
    declare -a failed=()
    # shellcheck disable=SC2043
    for test in ${lib.strings.concatStringsSep " " (map (t: t.name) limmatConfig.config.tests)}; do
      limmat-kernel --result-db "$LIMMAT_DB_PATH" test "$test" || failed+=("$test")
    done
    if [ ''${#failed[@]} -ne 0 ]; then
      echo "Failed tests:" "''${failed[@]}"
      exit 1
    fi
  '';
}
