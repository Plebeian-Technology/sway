---
lat:
  mode: explanation
---

# Design notes for the Ops settings group

`Sway::Settings::Ops` declares names sharing no common prefix (`env_prefix ""`), each read by a different consumer, among them:

- `SWAY_DEPLOYED_AT` — the deploy stamp `BootBackupGuard` compares against.
- `SWAY_SKIP_DB_BACKUP` — the switch that turns database backups off
  entirely.
- `IS_DOCKER` — whether this process runs inside a container.
- `DEV_TUNNEL_HOST` — the tunnel host a contributor's own Cloudflare tunnel
  serves the app from.
- `BESZEL_ADMIN_EMAIL_DOMAINS` — the email domains whose admins see the
  monitoring link ([[admin-hub-index#Who sees the monitoring link]]).

The phone number the notifications page shows is not here. It is the Twilio
sending number, a production credential, so it is read with the other Twilio
credentials ([[sms-notification-service-design#Where the displayed Sway number comes from]]).

## Why the frontend's IS_PRODUCTION reads the build, not the hostname

`app/frontend/sway_constants/index.ts`'s `IS_PRODUCTION` is decided by how the app was built, not the URL in the address bar.

A development build stays a development build whatever hostname serves it, so a contributor running their own Cloudflare tunnel (`DEV_TUNNEL_HOST`, above) is no longer mistaken for production — which used to send their local errors to Sentry and switch off `logDev`.
