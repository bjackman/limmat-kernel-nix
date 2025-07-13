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
- [x] Set up tests to ensure the configs all run against a golden kernel source,
      which can then be run via `nix flake check`.

      Note I tried this, but it's impossible to do this with a flake check and
      the current design, since it currently relies on doing `nix develop`, and
      that can't be done from inside the build sandbox. This does seem to
      confirm that we might be doing something fundementally bogus here. But,
      I'm not sure.

      Anyway, I worked around it by just hacking together an `apps` output that
      can be run for testing.
- [x] Figure out how to create `devShell`s for the scripts that get run in the
      Limmat config.
- [ ] Try to do some general niceness for configuration, like:
  - [ ] Configure the kernel using nice nix shit.
  - [ ] Avoid all the repetitive stuff like `make <one zillion flags>`  in the
        build script definitions