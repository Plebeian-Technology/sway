---
mode: explanation
summary: "Explains why Sway does not configure CORS: the app is same-origin in every environment, and what to do if that ever changes."
status: agent-extracted
related: []
---

# Same-origin design: why CORS is not configured

`config/application.rb` deliberately does not configure `rack-cors` or any
other CORS middleware. This documents why that gap is intentional rather
than an oversight.

## Sway is same-origin by design

- **Production:** Inertia.js serves React from the same Rails origin. No
  cross-origin browser traffic ever reaches the API.
- **ActionCable:** enforces its own origin checks on the WebSocket upgrade
  (`config.action_cable.allowed_request_origins`), independent of CORS.
- **Development:** the browser reaches the Vite dev server through Caddy on
  the same origin as the Rails app, and `rails_vite` sets the dev server's
  own origin and CORS settings. Neither path needs `rack-cors`.

Because every request path in every environment stays on one origin, there
is nothing for a CORS policy to grant or restrict.

## If a separate origin is ever needed

If Sway ever exposes JSON APIs to a genuinely separate origin — a mobile web
app, a third-party integration — introduce `rack-cors` at that point with a
strict allowlist, rather than adding it speculatively now.

Do not reach for `Rails::Application.config.action_controller.allow_origin`
instead: that is a different, narrower setting (it scopes to
`ActionController` responses only) and does not cover the general
cross-origin case `rack-cors` handles.
