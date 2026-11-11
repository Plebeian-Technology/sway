---
lat:
  mode: explanation
---

# Why Sway::Settings.build! pins the suppress switch narrowly

`Sway::Settings.build!` builds every registered group, pinning the suppress switch so `ANYWAY_SUPPRESS_VALIDATIONS` in the environment cannot turn the boot check off — but only that one variable.

An unconditional `Anyway::Settings.suppress_required_validations = false` here also overrode the gem's own `SECRET_KEY_BASE_DUMMY`-based suppression (`anyway/rails/settings.rb`), which is what lets `assets:precompile` inside a Docker image build boot in production mode with no real environment. Every attribute `required` in production happens to carry a default today, so that collision has not fired yet — it would surface as an opaque `docker build` failure at asset precompile, far from whatever `required`-with-no- default setting actually caused it (measured 2026-08-19 in code review).

`build!` instead sets:

```ruby
Anyway::Settings.suppress_required_validations = ENV.key?("SECRET_KEY_BASE_DUMMY")
```

so the gem's own Docker-build suppression path keeps working, and only a real `ANYWAY_SUPPRESS_VALIDATIONS` env var is neutralized.

`build!` also collects every group's validation failure instead of stopping at the first, and raises once naming them all together — so a Docker build or boot failure reports every missing setting in one pass, not one at a time across repeated retries.

## Why the kill-switch spec sets Anyway::Settings.suppress_required_validations directly, not just through with_env

`ANYWAY_SUPPRESS_VALIDATIONS` is read once, when the gem loads — setting it through `with_env` inside a running spec process changes nothing, since the gem already read the environment at boot.

What the environment variable actually DOES is set `Anyway::Settings.suppress_required_validations` directly, which is what `spec/lib/sway/settings_spec.rb`'s "the kill switch" examples reproduce explicitly, inside the same `with_env` block so the intent stays named next to the variable it stands in for. The flag is process-global, so each example resets it in an `ensure` block — leaving it `true` would silently disable required validation for every example that runs after it.
