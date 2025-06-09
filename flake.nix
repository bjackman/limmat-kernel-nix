{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.05";
    limmat.url = "github:bjackman/limmat";
  };

  outputs = inputs@{ self, nixpkgs, ... }: {
    packages =
      let
        # Other systems probably work too, I just don't have them to test. If you wanna try on Arm
        # or Darwin, add the system here, and if it works send a PR.
        supportedSystems = [ "x86_64-linux" ];
        forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      in
        forAllSystems (
          system:
          let
            pkgs = import nixpkgs { inherit system; };
            limmat = inputs.limmat.packages."${system}".default;
          in
          rec {
            limmatToml = pkgs.writeText "limmat.toml" ''
              [[tests]]
              name = "hello"
              command = "echo hello world"
            '';

            default = pkgs.stdenv.mkDerivation {
              pname = "limmat-kernel";
              version = "0.1.0";

              src = ./.;

              nativeBuildInputs = [ pkgs.makeWrapper ];

              installPhase = ''
                makeWrapper ${limmat}/bin/limmat $out/bin/limmat-kernel \
                  --set LIMMAT_CONFIG ${limmatToml}
              '';
            };
          });
  };
}
