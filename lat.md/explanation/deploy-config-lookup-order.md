---
lat:
  mode: explanation
---

# Why SwayDeployConfig looks up values the way it does

`SwayDeployConfig` holds the values that differ between one copy of Sway and another: which machine serves it, its optional Tailscale address, where that machine keeps its database, and which Google account holds its backups.

None of these are secrets. They are kept out of the tracked repository because they describe one deployment's network and cloud account — nobody else's copy can use them, and a public repo should not publish them.

## Lookup order

A value is looked for in this order:

1. An environment variable. This is how one deploy changes one value without
   editing any file.
2. `deploy/config/sway.env`, which git ignores. Each installation's own
   values live here — copy `deploy/config/sway.env.example` to create it.
3. Nothing. The run stops and names the value it could not find.

## Why there is no fourth step

This lookup deliberately has no default. A guessed default would send a deploy to the wrong machine, or upload backups to a bucket nobody reads. Both look exactly like success until the day somebody actually needs the value.

## The test exception

Tests are the one exception, and it is not a hidden one.

Under `RAILS_ENV=test`, the reader loads `deploy/config/sway.test.env` instead. That file *is* tracked, and every value in it is obviously fake. A test suite that needed somebody's real bucket name would fail on every other machine.

## Why this file avoids Rails and gems

`SwayDeployConfig` must not depend on Rails or on any gem. It is read before the autoloader exists: `config/deploy.yml` renders it through ERB, and `config/storage.yml` asks it for a project name while the app is still starting.
