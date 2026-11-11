---
lat:
  mode: explanation
---

# Why compose.yml env_file paths read through SWAY_SECRETS_ROOT

A phase runs in its own git worktree, and `git worktree add` brings across tracked files only.

Every `.env` file `.dockerdev/compose.yml` reads is untracked, so a worktree starts with none of them, and `docker compose` stops before it starts anything.

Copying the `.env` files into the worktree is not an option: they hold real Twilio, SendGrid, and VAPID keys, and a worktree is a tree an agent reads from and commits from. Instead, every `env_file` path in `compose.yml` reads through `SWAY_SECRETS_ROOT`, which names the main checkout and falls back to the current one. A bare `../` relative path resolves correctly only in the main checkout and nowhere else — `scripts/dip/secrets-root.sh` sets `SWAY_SECRETS_ROOT` before any other `dip` command runs, which is why `dip provision`, `dip run rspec`, and `dip run verify` call it themselves before doing anything else.

`spec/config/compose_secrets_root_spec.rb` checks that every `env_file` entry declared in `compose.yml` routes through `SWAY_SECRETS_ROOT` rather than a bare path, so a new service added without the indirection fails a worktree's compose run at boot instead of silently working only in the main checkout.
