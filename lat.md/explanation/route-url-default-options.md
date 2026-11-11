---
lat:
  mode: explanation
---

# Route URL defaults

The route draw reapplies shared URL defaults so generated URLs retain their configured host and protocol.

## Route redraws use the shared URL defaults

[[config/routes.rb]] merges the protocol with `config.x.default_url_options` whenever routes are drawn, rather than reading back a possibly replaced route-options hash.

Development sets the mailer host to `localhost:3000` but the externally reachable Caddy host to port `3333`; production supplies its deployed host to both consumers. Because drawing routes replaces the options hash, `config.x.default_url_options` is the source that lets generated URLs keep the externally reachable host after a redraw. [[config/environments/development.rb]] and [[config/environments/production.rb]] hold those environment values.
