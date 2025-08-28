{
  pkgs,
  stdenv,
  kernelSrc,
  requiredConfigs,
}:
stdenv.mkDerivation {
  name = "limmat-kernel-vm-kconfig";
  src = kernelSrc;
  nativeBuildInputs = with pkgs; [
    bison
    flex
    coreutils
  ];
  postPatch = ''
    patchShebangs scripts
  '';
  configurePhase = ''
    make $makeFlags defconfig
    echo "${toString requiredConfigs} | xargs -n 1 printf -- "--enable %s " | xargs scripts/config
  '';
  buildFlags = [ "olddefconfig" ];
  checkPhase = ''
    exit_code=0
    for conf in ${toString requiredConfigs}; do
      if [[ "$(scripts/config --state "$conf") != "y" ]]; then
        echo "$conf set in requiredConfigs but not set in final config"\
        exit_code=1
      fi
    end
    exit $exit_code
  '';
  installPhase = ''
    cp .config $out
  '';
}
