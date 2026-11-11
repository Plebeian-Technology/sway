---
lat:
  mode: explanation
---

# Why the settings initializer runs after :load_environment_config

`lib/sway/settings` is loaded by hand in `config/application.rb` rather than by the autoloader.

`lib/sway/settings` is loaded by hand in `config/application.rb` rather than by the autoloader: that file runs while the application is still being configured, before Zeitwerk is ready to resolve it (matches `config/environments/production.rb`'s own `require_relative` for the same reason).

## Why the ordering is load-bearing

The `sway.settings` initializer assembles every settings group.

The ordering is load-bearing, not decoration — `config/environments/#{Rails.env}.rb` is loaded by `:load_environment_config`, and `config/environments/test.rb` writes into the environment there (`SWAY_RELEASE_SHA`), so assembling any earlier would read a different world.

## What Sway::Settings.build! is responsible for

`build!` raises on any missing or unreadable setting — the assembly IS the point of running this here.

Nothing reads a return value: every group is read back through `Sway::Settings.<group>`, not `Rails.application.config.sway` (removed — no reader anywhere in the tree).
