DO NOT commit your changes, leave that to the human user. If you think it's time
to make a commit just say so, do NOT make a tool call to do the commit yourself.

This is a Go project but it is packaged with Nix (the configuration for this is
in the parent directory). The user might not have Go tools installed directly on
their workstation, instead they need to be run via Nix. The user may have run
you from within a Nix `devShell` in which case this is already taken care of and
you can just use `go` directly, but if that isn't in the `PATH` run it via `nix
develop .#test-runner -c <go cli args>`.

I repeat: DO NOT COMMIT. DO NOT RUN `git` operations except for inspecting
existing history. The human user will take care of writing commit messages. I
repeat: DO NOT COMMIT YOUR CHANGES TO GIT. You will really piss off the human if
you attempt to commit your changes yourself. Do not commit your changes. If you
think it's time to commit changes, inform the human but DO NOT MAKE THE COMMIT.