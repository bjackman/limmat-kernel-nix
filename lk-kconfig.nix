# Defines a script that generates a kconfig compatible with the lk-vm script.
{
  pkgs,
}:
let
  fragments = ./kconfigs;
in
pkgs.writeShellApplication {
  name = "lk-kconfig";
  runtimeInputs = [ pkgs.gnugrep ];
  runtimeEnv = {
    LK_KCONFIG_FRAGMENTS_DIR = fragments;
  };
  text = builtins.readFile ./lk-kconfig.bash;
}
