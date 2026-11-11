---
mode: explanation
summary: "Why scripts/dip/rspec.sh backgrounds its docker compose run and waits on it rather than running it in the foreground or with exec, so its cleanup trap can still fire."
status: agent-extracted
related: []
---

# Why `scripts/dip/rspec.sh` backgrounds its compose run

`scripts/dip/rspec.sh` must clean up after itself. Two ways to
lose that silently: `exec` stops any trap firing, since `exec` replaces the
shell that would run it; and a foreground command holds the trap until it
returns, so a signal sent to the script while the container is running
never reaches the trap in time.

`spec/scripts/dip_rspec_cleanup_spec.rb` pins the fix as backgrounding the
compose run and waiting on it (`compose ... run ... &` followed by `wait`),
so the trap can still fire while the container runs.

## What was measured

With the command in the foreground, `SIGTERM` to the
script leaves the container running. Backgrounded and waited on, it is
removed. Neither survives `SIGKILL`.

## Why the spec matches on the property, not on which command spells it

The regex matches on the shape (`compose ... run ... &` at end of line),
not on a specific command name. The script used to name `dip compose run`;
moving the suite onto `docker compose` directly — which is what lets it
carry a `-e` flag at all — turned a name-anchored check red while the
backgrounding it exists to protect was untouched.
