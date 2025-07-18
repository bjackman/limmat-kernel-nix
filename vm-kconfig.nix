# Defines a script that generates a kconfig compatible with the vm-run script.
{
  pkgs,
}:
# TODO: Hmm, this implicitly depends on the devShell. I'd like to just make this
# derivation explicitly aware of the tools from the devShell but as I found out
# this is pretty awkward. What do I do...?
pkgs.writeShellApplication {
  name = "limmat-kernel-vm-kconfig";
  runtimeInputs = [ pkgs.gnugrep ];
  text = ''
    make defconfig
    make kvm_guest.config
    scripts/config -e OVERLAY_FS
    make -j olddefconfig

    if ! grep -q OVERLAY_FS .config; then
        echo "OVERLAY_FS not defined in final config!"
        exit 1
    fi
  '';
}
