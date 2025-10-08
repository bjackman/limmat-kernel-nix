# Linux kernel dev environment

This is my development environment for the Linux kernel, defined in Nix. It is
mostly generic, but there are some aspects that are geared towards my particular
work. It should probably be split out into components that you can adopt into
your own flake and tune for your own workflow.

It's all x86-specific and only works on Linux. But it will work on any distro.

It is named after the fact that it includes a configuration for
[Limmat](https://github.com/bjackman/limmat), but it has a bit more than that
too.

Sharing configs and having everything Just Work is not really a key design goal
of Limmat. The idea here is to explore whether Nix can provide reproducibility
by acting as a layer on top of Limmat.

This works by using all the toolchains and stuff from nixpkgs, and defining the
config to refer directly to those binaries.

## Tasks and tips

### Modifying kselftests

The kselftests packaged into the VM by default is built from a fixed golden
kernel source. If you want to modify kselftests you have two options:

- Pass `--override-input kernel $kernel_tree` to whatever nix command is
  building the kselftsts (probably `nix develop`). This is kinda slow but easy
  if you just want to run with a modification for a certain time.

- To avoid having a slow Nix command in your dev cycle, you can instead build
  and run the kselftests manually from your shell:

  - Run `make -C tools/testing/selftests TARGETS="kvm" -sj100
    EXTRA_CFLAGS=-static` (update `TARGETS` to build other selftests)

  - Boot the VM with `lk-vm`'s `--tree` argument pointing to your kernel tree.

  - In the guest, `cd /mnt/kernel/tools/testing/selftests` and run them from
    there. This is a live 9pfs share so you can rebuild in the host and re-run
    without rebooting the guest.

## TODO

- [x] Make kernel config biz more flexible
- [x] Make kselftest running more flexible
- [ ] Document shit
- [ ] Support running on other host architectures
- [ ] Supoport running guests of other architectures
- [ ] [Support running on
       MacOS](https://seiya.me/blog/building-linux-on-macos-natively)??
- [ ] Figure out how to make it more like a library you can customize isntead if
      getting all my personal shit along with the generic frameworky stuff.
- [x] Consider making kernel config biz more flexible still. At the moment it
      doesn't capture which options are really needed and which are there to
      satisfy dependencies.
