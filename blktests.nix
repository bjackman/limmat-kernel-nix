# Simple package for blktests that basically produces its "check" script.
# Note this won't actually work unless you set the --output arg.
{
  pkgs,
  lib,
  stdenv,
  inputs,
}:
let
  runtimeInputs = with pkgs; [
    bash
    coreutils # dd, stat, realpath
    fio
    gawk
    gzip # zgrep
    kmod # modprobe
    udev # udevadm
    util-linux # blockdev, dmesg, logger, column
    bc
  ];
in
stdenv.mkDerivation {
  pname = "blktests";
  version = "unstable";
  src = inputs.blktests;

  makeFlags = [ "prefix=${placeholder "out"}" ];

  nativeBuildInputs = [ pkgs.makeWrapper ];

  buildInputs = with pkgs; [
    liburing
    linuxHeaders
  ];

  postInstall = ''
    wrapProgram $out/blktests/check --prefix PATH : ${lib.makeBinPath runtimeInputs}

    mkdir -p $out/bin
    cat <<EOF > $out/bin/blktests
    #!/bin/sh
    cd $out/blktests || exit 1
    exec ./check "\$@"
    EOF

    chmod +x $out/bin/blktests
  '';
}
