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

## Checkpatch

The Limmat config includes `checkpatch` test that runs checkpatch while ignoring
some basic stuff. This also allows overriding the checkpatch config for
individual commits, but this support is half baked until
https://github.com/bjackman/limmat/pull/39 can be submitted.

To disable checkpatch warnings:

- `git notes --ref=limmat append -m "checkpatch-ignore=$CATEGORY" $COMMIT`.

- Restart Limmat.

## HOWTOs

Start by running `nix develop path/to/this/repo#kernel`. This will always drop
you in a Bash shell, you can add `-c fish` or whatever to run a different
command such as your preferred shell.

### Boot a VM

Generate a kconfig that has the necessary features to boot in the VM:

```
lk-kconfig "base vm-boot"
```

Now build your kernel (e.g. `make -sj100 bzImage`).

Then assuming you built the kernel in your current directory, you can boot that
kernel in a VM with:

```
lk-vm --tree .
```

This will also mount your kernel tree at `/mnt/kernel/` in the VM.

##### ... with defconfig

If you wanna test defconfig instead of a minimal config provided by
`lk-kconfig`, something like this should give you a working kconfig:

```sh
make defconfig
make kvm_guest.config
scripts/config -e OVERLAY_FS -e ZRAM -e ZSWAP
```

#### Run kselftests

##### Pre-packaged kselftests

`lk-vm` boots up with kselftests installed, as built from a fixed golden kernel
source. You can run this via the `ktests` CLI which is in the `$PATH` after
booting the VM.

```sh
# Run all available kselftests directly:
ktests kselftests.*
# Run a specific KVM selftest:
ktests kselftests.kvm.amx_test
# The mm selftests ("vmtests") also have special packaging to work around the
# janky kernel scripts:
ktests vmtests.mmap
```

The raw `run_kselftest.sh` is also in your path, in case you want to run that
directly.

##### Modified kselftests (fast/janky process)

Warning: janky workflow ahead.

TODO: Due to https://github.com/NixOS/nixpkgs/issues/59267, the `devShell`
provided by this repo can't provide a static glibc, so you'll need to set up the
build environment for this outside of Nix :(. An alternative to this janky
workflow, which doesn't have this problem, would be to build the kselftests via
nix with `--override-input`.

Warning: the kselftests Makefiles are bad, you will generally need to
make liberal  use of `make -C tools/testing/selftests clean`.

Basically: build the kselftests in your kernel tree on the host, then run them
in the VM via the 9pfs mount.

```sh
# From kernel tree, on the host. Update TARGETS depending on which tests you want to run.
make -C tools/testing/selftests  TARGETS="kvm" -sj100 EXTRA_CFLAGS=-static install
```

In the guest:

```sh
cd /mnt/kernel/tools/testing/selftests/kselftest_install
./run_kselftest.sh -t kvm:amx_test  # Or whatever test you wanna run.
```

##### Modified kselftests (slow/Nix-based process)

Basically: pass `--override-input kernel path/to/kernel/tree` to whatever `nix`
command builds your kselftests. This might be `nix develop` if you don't need to
iterate on the tests themselves.

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
