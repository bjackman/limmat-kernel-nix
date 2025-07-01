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

        checks = {
          # Check formatting.
          #
          # TODO: This is dumb, there has to be a simple way to configure this.
          # There's https://github.com/numtide/treefmt-nix but it's also
          # over-engineered.
          format =
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
          # Check that the tests defined in the Limmat config pass against a
          # reference kernel source. The kernel from nixpkgs is a reasonable
          # choice for this.
          test =
            let
              refKernel = pkgs.linuxPackages.kernel;
            in
            pkgs.runCommand "test-limmat-config" { } ''
              set -eux
              cd $TMPDIR

              ${pkgs.gnutar}/bin/tar xf ${refKernel.src}
              cd linux-${refKernel.version}

              # By default limmat logs to your home dir (dumb?). This isn't
              # accessible from the sandbox.
              export LIMMAT_LOGFILE=$TMPDIR/limmat.log

              # Limmat fails if you aren't in a Git repository with commits in
              # it.
              ${pkgs.git}/bin/git init
              ${pkgs.git}/bin/git config user.email chung.flunch@example.com
              ${pkgs.git}/bin/git config user.name "Chungonius Flunchér XIII"
              ${pkgs.git}/bin/git add .
              ${pkgs.git}/bin/git commit -m "init fake repo to make limmat happy"

              ${self.packages."${system}".limmat-kernel}/bin/limmat-kernel \
                --git-binary ${pkgs.git}/bin/git --result-db $TMPDIR/limmat-db \
                test build_min
              touch $out
            '';
        };

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
      }
    );
}
