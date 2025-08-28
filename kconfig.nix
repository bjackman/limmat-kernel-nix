# Derivation to build a kconfig file.
{
  pkgs,
  stdenv,

  # Required args:
  kernelSrc,
  # List of kconfigs that you want to be enabled (=y). They may omit the CONFIG_
  # from the beginning.
  requiredConfigs,
}:
stdenv.mkDerivation {
  name = "kconfig";
  src = kernelSrc;
  nativeBuildInputs = with pkgs; [
    bison
    flex
    coreutils
  ];
  enableParallelBuilding = true;
  postPatch = ''
    patchShebangs scripts
  '';
  configurePhase = ''
    make $makeFlags defconfig
    echo ${toString requiredConfigs} | xargs -n 1 printf -- "--enable %s " | xargs scripts/config
  '';
  buildFlags = [ "olddefconfig" ];
  doCheck = true;
  checkPhase = ''
    errors=false
    for conf in ${toString requiredConfigs}; do
      if [[ "$(scripts/config --state "$conf")" != "y" ]]; then
        echo "$conf set in requiredConfigs but not 'y' in final config"
        errors=true
      fi
    done
    if $errors; then
      exit 1
    fi
  '';
  installPhase = ''
    cp .config $out
  '';
}
