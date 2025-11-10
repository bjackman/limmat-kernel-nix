{
  pkgs,
  lib,
  # The main package of this repository.
  limmat-kernel,
  # The Limmat configuration defined by this repository as a Nix attrset.
  limmatConfig,
  kernelSrc,
}:
pkgs.writeShellApplication {
  name = "limmat-kernel-test-golden";
  runtimeInputs = [
    pkgs.gnutar
    pkgs.git
    limmat-kernel
  ];
  text = ''
    TMPDIR="''${TMPDIR:-/tmp}"
    GOLDEN_KERNEL_TREE="''${GOLDEN_KERNEL_TREE:-"$TMPDIR"/lkn-golden-kernel}"
    set -eux -o pipefail
    mkdir -p "$GOLDEN_KERNEL_TREE"
    cd "$GOLDEN_KERNEL_TREE"

    # Set a hard-coded date to try and make the commit hash
    # deterministic.
    export GIT_AUTHOR_DATE="2000-01-01T00:00:00Z"
    export GIT_COMMITTER_DATE="2000-01-01T00:00:00Z"
    GOLDEN_COMMIT_HASH=6eade1a88927a144f50d194491b5b89a3e0aa962

    # If we just have a Nix derivation that produces a kernel
    # repository then Limmat will fall over because the .git dir
    # has what Git describes as "dubious permissions". So instead
    # we do this silly dance to set up a golden tree in a
    # relatively reproducible way.
    if [ -e .git ]; then
      git reset --hard
      git clean -fdx
      commit_hash="$(git rev-parse HEAD)"
      if [ "$commit_hash" != "$GOLDEN_COMMIT_HASH" ]; then
        echo "Unexpected commit hash $commit_hash"
        echo "try deleting $GOLDEN_KERNEL_TREE and restarting."
        exit 1
      fi
    else
      # Copy preserving permissions but setting the writable bit
      rsync -a --chmod=u+w ${kernelSrc}/* .

      # By default limmat logs to your home dir (dumb?).
      export LIMMAT_LOGFILE=$TMPDIR/limmat.log

      # Limmat fails if you aren't in a Git repository with commits in
      # it.
      git init
      git config user.email chung.flunch@example.com
      git config user.name "Chungonius Flunchér XIII"
      git add .
      git commit -m "init fake repo to make limmat happy"

      # We'll run checkpatch which falls over if there isn't a vaguely realistic
      # commit at HEAD.
      echo "/* ok */" >> mm/page_alloc.c
      git commit --signoff -m "another commit to avoid DoSing checkpatch" mm/page_alloc.c

      commit_hash="$(git rev-parse HEAD)"
      if [ "$commit_hash" != "$GOLDEN_COMMIT_HASH" ]; then
        echo "Unexpected commit hash $commit_hash"
        echo "Please update GOLDEN_COMMIT hash in this script"
        exit 1
      fi
    fi

    # Disable warning if loop always has exactly one iteration.
    declare -a failed
    # shellcheck disable=SC2043
    for test in ${lib.strings.concatStringsSep " " (map (t: t.name) limmatConfig.config.tests)}; do
      limmat-kernel --result-db "$TMPDIR"/limmat-db test "$test" || failed+=("$test")
    done
    if [ ''${#failed[@]} -eq 0 ]; then
      echo "Failed tests:" "''${failed[@]}"
      exit 1
    fi
  '';
}
