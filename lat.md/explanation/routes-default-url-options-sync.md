---
lat:
  mode: explanation
---

# Why default_url_options is re-applied in routes.rb

Assigning only `protocol:` replaces the WHOLE options hash on every routes reload, so `*_url` helpers lost the host/port `config/environments` sets at boot.

Assigning only `protocol:` replaces the WHOLE options hash on every routes reload, so `*_url` helpers lost the host/port `config/environments` sets at boot — legislator photos then resolved to the mailer's port 3000, a different origin than Caddy's 3333, and the browser refused them. `config/routes.rb` reads the host from config, never from the current value: reading back the current value can't recover a server that already lost it, and would just merge the damage forward until a full restart.

```ruby
default_url_options(
  {protocol: ENV.fetch("APP_PROTOCOL", "https")}
    .merge(Rails.application.config.x.default_url_options || {})
)
```

## Development: why config.x.default_url_options is set separately

`config/environments/development.rb` sets `config.x.default_url_options` because it is read by `config/routes.rb`, which re-applies these every time it is re-read.

Assigning `Rails.application.routes.default_url_options` directly instead only held until the first routes reload, because drawing the routes replaces the whole hash. The browser talks to Caddy on port 3333; the mailer settings in the same file name port 3000, which is the Rails container and a different origin.

## Production: why both the mailer assignment and config.x are set

`config/environments/production.rb` sets both, on purpose.

The mailer assignment (`config.action_mailer.default_url_options = default_url_options`) sets the value now; `config.x.default_url_options` is what `config/routes.rb` re-applies each time it draws the routes, which would otherwise replace the hash with the protocol alone and drop the host.
