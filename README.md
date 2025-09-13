# Limmat config for kernel dev, BUT IN NIX

Experiment in setting up something like
[limmat-kernel](https://github.com/bjackman/limmat-kernel) but in Nix.

Sharing configs and having everything Just Work is not really a key design goal
of Limmat. The idea here is to explore whether Nix can provide reproducibility
by acting as a layer on top of Limmat.

This works by using all the toolchains and stuff from nixpkgs, and defining the
config to refer directly to those binaries.

## TODO

- [x] Make kernel config biz more flexible
- [ ] Make kselftest running more flexible
- [ ] Document shit
- [ ] Figure out how to make it more like a library you can customize isntead if
      getting all my personal shit along with the generic frameworky stuff.
- [ ] Consider making kernel config biz more flexible still. At the moment it
      doesn't capture which options are really needed and which are there to
      satisfy dependencies.