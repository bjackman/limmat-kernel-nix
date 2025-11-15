# Defines a script that generates a kconfig compatible with the lk-vm script.
{
  pkgs,
}:
let
  # Interpolating ./kconfigs into a string is important here, it causes the
  # content to be build into a separate derivation with its own hash. Otherwise,
  # it just refers to the kconfigs subdirectory of the source derivation for the
  # overall flake. That turns out to be really undesirable because that
  # derivation path changes if anything in the flake changes, which means that
  # this derivation ends up being different even if none of the files it refers
  # to changed.
  fragments = "${./kconfigs}";
in
pkgs.writeShellApplication {
  name = "lk-kconfig";
  runtimeInputs = with pkgs; [
    gnugrep
    getopt
  ];
  runtimeEnv = {
    LK_KCONFIG_FRAGMENTS_DIR = fragments;
  };
  text = builtins.readFile ./lk-kconfig.bash;
}
