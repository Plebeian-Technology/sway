---
lat:
  mode: explanation
---

# New Relic license key boot-time normalization

Why `config/boot.rb` normalizes `NEW_RELIC_LICENSE_KEY` in place, in plain Ruby, before `bundler/setup` even runs.

## Why this credential skips EnvSecret

Every other credential in Sway reads `ENV` through `app/lib/env_secret.rb`, the one path the codebase allows for that. New Relic's license key cannot go through that path.

The `newrelic_rpm` gem builds its own `EnvironmentSource` straight off `ENV` (`environment_source.rb:78`: `self[config_key] = ENV[key]`, with no stripping), and `manager.rb:549-554` orders the config stack as `[high_security, ENVIRONMENT, server, manual, YAML, default]`. The `ENV` value shadows `config/newrelic.yml` whenever it is set — exactly how Kamal injects it in production. Sway's own code has no call site to route through `EnvSecret`, because the gem reads the variable itself, and no ERB template to strip whitespace from, because the gem never touches `newrelic.yml`'s ERB layer once `ENV` has a value.

This was verified against `newrelic_rpm` 10.6.0: with `NEW_RELIC_LICENSE_KEY="nrlk_abc\n"` set, `EnvironmentSource.new[:license_key]` returns `"nrlk_abc\n"` — trailing whitespace and all.

## Why boot.rb, and why plain Ruby

The variable has to be clean before the gem loads, and `config/boot.rb` is the earliest Ruby this process runs — before `bundler/setup`, let alone Zeitwerk.

`EnvSecret` isn't available yet at that point in boot, so the normalization is plain Ruby rather than a call into it.

## Why delete instead of blanking

When the stripped value is empty, `boot.rb` deletes the key from `ENV` rather than setting it to `""`.

New Relic's `EnvironmentSource` would still treat `""` as a supplied value, overriding `config/newrelic.yml`'s license with an empty one. Deleting the key is the honest representation of "no credential was supplied," letting the YAML config (or its absence) take over normally.
