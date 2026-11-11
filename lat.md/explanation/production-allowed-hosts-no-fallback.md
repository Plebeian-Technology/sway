---
lat:
  mode: explanation
---

# Why there is no fallback for RAILS_ALLOWED_HOSTS

Which names and addresses the production machine will answer to is NOT written in `config/environments/production.rb`: the list holds deployment-specific addresses, which do not belong in the repository.

`config/deploy.yml` passes it in from `deploy/config/sway.env`.

There is no fallback on purpose. A guessed list is the kind of mistake that looks like a working deploy until somebody reaches the site by an address nobody thought of, and then every request is refused before it reaches any code that could explain why.

## Development allowed hosts and DEV_TUNNEL_HOST

[[config/environments/development.rb]] permits `.ngrok-free.app` for ad-hoc tunnel testing, `.ts.net` for Tailscale devices, `web` for internal Docker service-to-service traffic, and an optional `DEV_TUNNEL_HOST` hostname.

When `Sway::Settings.dev.tunnel_host` is present, development appends that hostname (such as `<dev-tunnel-host>`) so requests arriving through a named Cloudflare tunnel pass `ActionDispatch::HostAuthorization`.
