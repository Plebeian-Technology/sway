---
lat:
  mode: explanation
---

# Why RateLimits kill switches default to true and validate strictly

`Sway::Settings::RateLimits` (`lib/sway/settings/rate_limits.rb`) declares ten independent kill switches, one per throttled endpoint.

Each defaults to `true` (security-first): once an endpoint is throttled in production, it stays throttled unless an operator explicitly opts out. The gem's own `:boolean` caster answers `false` for a blank value; it is `Base`'s replacement caster and blank repair that make a blank env variable read back as `true` here, not the gem's own default behavior.

The design asked for one table rather than ten fields, because `RateLimitConfig`'s `FLAG_FOR` already reads well and ten fields would duplicate it. The gem binds one attribute per environment variable, so ten attributes is the only shape that reads ten variables — but they exist only inside this settings file. The one table keyed by scope stays exactly where it was, in `RateLimitConfig`, still raising on an unknown scope.

## Why the typo guard reads the raw env value

The shared `:boolean` caster (`Base`) answers `false` for *any* unrecognized non-blank text.

The shared `:boolean` caster (`Base`) answers `false` for *any* unrecognized non-blank text — deliberately, for the three other settings groups that declare a `:boolean` and want "unreadable" to land on their safe side without crashing boot (see `Base`'s comment on its `:boolean` registry entry).

This group is the one place that shape is actually dangerous: every switch here defaults to `true` (protected), so a caster-returned `false` is not `nil`, `Base`'s blank repair never fires, and a one-letter typo (`"ture"`) would switch a throttle off permanently with no error anywhere. The `on_load` hook that validates this reads the *raw* env value, because by the time an `on_load` callback runs, the caster has already thrown the original text away.

## Why the preferences scope is rate-limited by IP

`Users::PreferencesController#update` skips the usual cross-site request check for callers using a bearer token, and skips sign-in entirely for the anonymous signed-cookie path.

The per-IP throttle on that scope is what limits how often one IP address can hit that anonymous PATCH endpoint, compensating for the two checks it does not get.

## Why the blank-repair spec builds a fresh settings instance per variable

`spec/lib/rate_limit_config_spec.rb`'s "blank repair.

`spec/lib/rate_limit_config_spec.rb`'s "blank repair, one per variable" examples vary the raw `RATE_LIMIT_*` env variable rather than the setting, because they are pinning what the declaration itself does with a blank input, not what `RateLimitConfig.enabled?` reads. `Sway::Settings.rate_limits` is memoized, so setting the env var with `with_env` alone would never reach the new value through `.enabled?` — the memoized instance was already built. Each example instead calls `Sway::Settings::RateLimits.new` directly, sidestepping the memoization entirely and proving the blank-repair behavior for all ten kill-switch variables independently.

## Why repeated rate-limit blocks alert fail-open through the cache

Repeated rate-limit rejections indicate active credential stuffing or scraping campaigns. Sway tracks repeated blocks per actor in the cache and emits throttled operational alerts without delaying client responses.

[[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#report_repeated_rate_limit]] coordinates alerting when an incoming request trips [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#render_rate_limited]]. The method resolves an actor identifier based on whether the caller is signed in (`user:<id>`) or unauthenticated (`ip:<remote_ip>`). Rather than recording occurrences in the database, Sway increments an actor-specific counter in `Rails.cache` bounded by [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#REPEATED_BLOCK_WINDOW]]. This ephemeral cache counter prevents database transaction overhead on high-frequency request rejections.

Alerting is throttled to avoid overwhelming notification channels during automated sweeps. An initial alert fires when an actor reaches [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#REPEATED_BLOCK_THRESHOLD]] blocks within the five-minute window, followed by sampled alerts on multiples of [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#SENTRY_ALERT_SAMPLE_RATIO]]. Each alert records a structured warning via [[lib/sway_logging.rb#SwayLogging#warn]] and dispatches a warning message to Sentry.

Operational telemetry remains strictly non-blocking. Any exception arising during counter increments, logging, or Sentry dispatch is caught by a fail-open error boundary. Even during complete cache or telemetry backend outages, [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#render_rate_limited]] completes normally, setting the `Retry-After: 60` response header and returning the expected rate-limited HTTP status without crashing into an unhandled server error.
