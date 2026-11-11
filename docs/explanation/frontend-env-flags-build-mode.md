---
mode: explanation
summary: "Why Sway's frontend dev/production flags are derived from Vite's build mode rather than window.location.hostname, and the DEV_TUNNEL_HOST bug that caused the switch."
status: agent-extracted
related: []
---

# Why the frontend env flags read build mode, not hostname

These flags used to be worked out from `window.location.hostname`, checked
against a list of two allowed names. Any other development host — a
contributor's own Cloudflare tunnel (`DEV_TUNNEL_HOST`), for one — counted as
production, which shipped their local errors to Sentry and silenced `logDev`.
The build mode decides now, and these tests keep it that way.
