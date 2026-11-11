---
lat:
  mode: explanation
---

# Why SeedLog writes to stdout, not just Rails.logger

Seed scripts otherwise log only via `Rails.logger.*`, which in a one-off `dip run rails seed` container is written to `log/development.log` — never the terminal.

During a long run (especially the network-heavy bills pipeline) the console looks frozen even though seeding is progressing.

`SeedLog.say` writes a milestone to BOTH the terminal (stdout, flushed so it appears immediately under Docker) AND the Rails log. stdout is suppressed in the test environment so RSpec output stays clean.
