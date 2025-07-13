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
        apps.test-golden = {
          type = "app";
          program =
            let
              pkg = pkgs.callPackage ./test-golden.nix {
                # Passing packages "manually" as a normal arg like this might be
                # in poor taste, I'm not sure. Like maybe the "proper" way is via
                # a nixpkgs overlay or something like that.
                limmat-kernel = self.packages."${system}".limmat-kernel;
                inherit limmatConfig;
              };
            in
            "${pkg}/bin/limmat-kernel-test-golden";
        };
      }
    );
}
