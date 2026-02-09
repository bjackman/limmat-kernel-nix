{ stdenv }:
stdenv.mkDerivation rec {
  name = "guest-memfd-test";
  version = "0.1";
  src = ./.;
  buildPhase = ''
    $CC guest_memfd_test.c -o guest_memfd_test
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp guest_memfd_test $out/bin/${name}
  '';
}