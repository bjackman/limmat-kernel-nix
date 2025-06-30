# Limmat config for kernel dev, BUT IN NIX

Experiment in setting up something like
[limmat-kernel](https://github.com/bjackman/limmat-kernel) but in Nix.

Sharing configs and having everything Just Work is not really a key design goal
of Limmat. The idea here is to explore whether Nix can provide reproducibility
by acting as a layer on top of Limmat.

This works by using all the toolchains and stuff from nixpkgs, and defining the
config to refer directly to those binaries.

## TODO

- [ ] Get all the tasks from `limmat-kernel` coded up via a Nix config.
- [ ] Set up tests to ensure the configs all run against a golden kernel source,
      which can then be run via `nix flake check`.
- [x] Figure out how to create `devShell`s for the scripts that get run in the
      Limmat config.
- [ ] Try to do some general niceness for configuration, like:
  - [ ] Configure the kernel using nice nix shit.
  - [ ] Avoid all the repetitive stuff like `make <one zillion flags>`  in the
        build script definitions