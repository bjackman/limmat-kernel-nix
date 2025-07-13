# Check all the .nix files are formatted.
# This is designed yto be run as a "check" i.e you just build it, it produces an
# empty output.
# TODO: This is dumb, there has to be a simple way to configure this.
# There's https://github.com/numtide/treefmt-nix but it's also
# over-engineered.
{ pkgs, lib }:
pkgs.runCommand "check-nix-format"
  {
    nativeBuildInputs = [ pkgs.nixfmt-rfc-style ];
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.gitTracked ./.;
    };
    output = "/dev/null";
  }
  ''
    for file in $(find $src -name "*.nix"); do
    nixfmt --check $file
    done
    touch $out
  ''
