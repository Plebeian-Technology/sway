---
mode: reference
summary: "Documents the order Sway::Settings resolves a value in, and how it relates to Sway's other two environment-reading doors."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Sway::Settings value resolution

`Sway::Settings` is the third door a running Sway reads its environment
through, replacing scattered `ENV[...]` reads with one declared class per
group.

## Where a value comes from, in order

1. An environment variable, matched to its bare name by the group's empty
   `env_prefix`.
2. The attribute's declared default, when the value is blank or unset —
   blank counts as absent everywhere.
3. Nothing. `build!` raises once, naming every group's missing or unreadable
   settings together.

## The other two doors

- **`EnvSecret`** (`app/lib/env_secret.rb`) — the credential door, for every
  name Kamal pushes as `env: secret:` in `config/deploy.yml`. `Sway::Settings`
  never re-exposes a credential.
- **`SwayDeployConfig`** (`lib/sway_deploy_config.rb`) — which machine, which
  buckets, where the database lives. Runs before Rails exists and falls back
  to a git-ignored file, which `Sway::Settings` cannot read.
