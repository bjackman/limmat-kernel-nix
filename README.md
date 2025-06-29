# Limmat config for kernel dev, BUT IN NIX

Experiment in setting up something like
[limmat-kernel](https://github.com/bjackman/limmat-kernel) but in Nix.

Sharing configs and having everything Just Work is not really a key design goal
of Limmat. The idea here is to explore whether Nix can provide reproducibility
by acting as a layer on top of Limmat.

This works by using all the toolchains and stuff from nixpkgs, and defining the
config to refer directly to those binaries.

At present it tries to avoid being too clever with Nix, aside from that. This
means that the configuration is much more verbose than you might expect: Nix
makes it very easy to build red blooded American software with a Makefile. But,
all the magic in nixpkgs to make that happen is designed for _building
software_, not for building software that builds software. It's not really
designed to do stuff like make headers available _at runtime_ which is what's
needed here. Thus, this config kinda recreates some of that logic with a
different goal in mind.

## TODO

- [ ] Get all the tasks from `limmat-kernel` coded up via a Nix config.
- [ ] Set up tests to ensure the configs all run against a golden kernel source,
      which can then be run via `nix flake check`.
- [ ] Figure out how to create `devShell`s for the scripts that get run in the
      Limmat config.
- [ ] Try to do some general niceness for configuration, like:
  - [ ] Configure the kernel using nice nix shit.
  - [ ] Avoid all the repetitive stuff like `make <one zillion flags>`  in the
        build script definitions