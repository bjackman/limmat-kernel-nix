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

    # Hm, need some more flexible way to configure this. For now, it's harmless
    # to just enable it everywhere I think.
    scripts/config -e GUP_TEST

    scripts/config -e DEBUG_KERNEL -e DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT -e GDB_SCRIPTS

    make -j olddefconfig

    if ! grep -q OVERLAY_FS .config; then
        echo "OVERLAY_FS not defined in final config!"
        exit 1
    fi
  '';
}
