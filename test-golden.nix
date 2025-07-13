{
  pkgs,
  lib,
  limmat-kernel,
  limmatConfig,
}:
let
  refKernel = pkgs.linuxPackages.kernel;
in
pkgs.writeShellApplication {
  name = "limmat-kernel-test-golden";
  runtimeInputs = [
    pkgs.gnutar
    pkgs.git
    limmat-kernel
  ];
  text = ''
    TMPDIR="''${TMPIR:-/tmp}"
    GOLDEN_KERNEL_TREE="''${GOLDEN_KERNEL_TREE:-"$TMPDIR"/lkn-golden-kernel}"
    set -eux -o pipefail
    mkdir -p "$GOLDEN_KERNEL_TREE"
    cd "$GOLDEN_KERNEL_TREE"

    # Set a hard-coded date to try and make the commit hash
    # deterministic.
    export GIT_AUTHOR_DATE="2000-01-01T00:00:00Z"
    export GIT_COMMITTER_DATE="2000-01-01T00:00:00Z"
    GOLDEN_COMMIT_HASH=a4b04c10828e88f9299e1f6d16c25de915d1e94b

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
      # The src repo contains seomthing like linux-6.6.1/, the
      # --strip components strips that out and directly extracts
      # the contents of that dir.
      tar --strip-components=1 -xf ${refKernel.src}

      # By default limmat logs to your home dir (dumb?).
      export LIMMAT_LOGFILE=$TMPDIR/limmat.log

      # Limmat fails if you aren't in a Git repository with commits in
      # it.
      git init
      git config user.email chung.flunch@example.com
      git config user.name "Chungonius Flunchér XIII"
      git add .
      git commit -m "init fake repo to make limmat happy"
      commit_hash="$(git rev-parse HEAD)"
      if [ "$commit_hash" != "$GOLDEN_COMMIT_HASH" ]; then
        echo "Unexpected commit hash $commit_hash"
        echo "Please update GOLDEN_COMMIT hash in this script"
        exit 1
      fi
    fi

    # Disable warning if loop always has exactly one iteration.
    # shellcheck disable=SC2043
    for test in ${lib.strings.concatStringsSep " " (map (t: t.name) limmatConfig.tests)}; do
      limmat-kernel --result-db "$TMPDIR"/limmat-db test "$test"
    done
  '';
}
