---
mode: explanation
summary: "What each of Sway::Settings::Ops's five names is for and which consumer reads it, since none of them share a common prefix."
status: agent-extracted
related: [settings-group-declaration-notes]
---

<!-- vale Vale.Spelling = NO -->

# Design notes for the Ops settings group

`Sway::Settings::Ops` declares five names sharing no common prefix
(`env_prefix ""`), each read by a different consumer:

- `SWAY_SMS_PHONE` — the phone number the notifications page shows.
- `SWAY_DEPLOYED_AT` — the deploy stamp `BootBackupGuard` compares against.
- `SWAY_SKIP_DB_BACKUP` — the switch that turns database backups off
  entirely.
- `IS_DOCKER` — whether this process runs inside a container.
- `DEV_TUNNEL_HOST` — the tunnel host a contributor's own Cloudflare tunnel
  serves the app from.

## Why the frontend's `IS_PRODUCTION` reads the build, not the hostname

`app/frontend/sway_constants/index.ts`'s `IS_PRODUCTION` is decided by how
the app was built, not the URL in the address bar. A development build
stays a development build whatever hostname serves it, so a contributor
running their own Cloudflare tunnel (`DEV_TUNNEL_HOST`, above) is no
longer mistaken for production — which used to send their local errors to
Sentry and switch off `logDev`.
