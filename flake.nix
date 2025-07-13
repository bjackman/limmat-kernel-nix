{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    limmat.url = "github:bjackman/limmat";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        limmat = inputs.limmat.packages."${system}".default;
        limmatConfig = (pkgs.callPackage ./limmat-config.nix { }).config;
        format = pkgs.formats.toml { };
      in
      {
        formatter = pkgs.nixfmt-tree;

        # Check formatting.
        # TODO: This is dumb, there has to be a simple way to configure this.
        # There's https://github.com/numtide/treefmt-nix but it's also
        # over-engineered.
        checks.default =
          pkgs.runCommand "check-nix-format"
            {
              nativeBuildInputs = [ pkgs.nixfmt-rfc-style ];
              src = nixpkgs.lib.fileset.toSource {
                root = ./.;
                fileset = nixpkgs.lib.fileset.gitTracked ./.;
              };
              output = "/dev/null";
            }
            ''
              for file in $(find $src -name "*.nix"); do
                nixfmt --check $file
              done
              touch $out
            '';

        packages = rec {
          limmatTOML = format.generate "limmat.toml" limmatConfig;

          limmat-kernel = pkgs.stdenv.mkDerivation {
            pname = "limmat-kernel";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              makeWrapper ${limmat}/bin/limmat $out/bin/limmat-kernel \
                --set LIMMAT_CONFIG ${limmatTOML}
            '';
          };
          default = limmat-kernel;
        };

        # Because of the hackery involved in this system, where we use `nix
        # develop` from within the config, this can't be tested via a normal
        # flake check which would run inside the build sandbox. So instead the
        # tests for the config are exposed as an app that is run
        # non-hermetically.
        apps.test = {
          type = "app";
          program =
            let
              refKernel = pkgs.linuxPackages.kernel;
              pkg = pkgs.writeShellApplication {
                name = "limmat-kernel-test-golden";
                runtimeInputs = [
                  pkgs.gnutar
                  pkgs.git
                  self.packages."${system}".limmat-kernel
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
                  for test in ${pkgs.lib.strings.concatStringsSep " " (map (t: t.name) limmatConfig.tests)}; do
                    limmat-kernel --result-db "$TMPDIR"/limmat-db test "$test"
                  done
                '';
              };
            in
            "${pkg}/bin/limmat-kernel-test-golden";
        };
      }
    );
}
