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

### HOWTOs

#### Boot an `lk-vm` with defconfig

```sh
make defconfig
make kvm_guest.config
scripts/config -e OVERLAY_FS -e ZRAM -e ZSWAP
```

This should give you a bzImage that boots.

## TODO

- [x] Make kernel config biz more flexible
- [x] Make kselftest running more flexible
- [ ] Document shit
- [ ] Properly support getting a bootable config starting from defconfig
- [ ] Support running on other host architectures
- [ ] Supoport running guests of other architectures
- [ ] [Support running on
       MacOS](https://seiya.me/blog/building-linux-on-macos-natively)??
- [ ] Figure out how to make it more like a library you can customize isntead if
      getting all my personal shit along with the generic frameworky stuff.
- [x] Consider making kernel config biz more flexible still. At the moment it
      doesn't capture which options are really needed and which are there to
      satisfy dependencies.
