---
mode: explanation
summary: "Explains why RateLimits' ten kill switches default to true and why the group re-validates raw env text instead of trusting the shared boolean caster."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why RateLimits kill switches default to true and validate strictly

`Sway::Settings::RateLimits` (`lib/sway/settings/rate_limits.rb`) declares ten
independent kill switches, one per throttled endpoint. Each defaults to
`true` (security-first): once an endpoint is throttled in production, it
stays throttled unless an operator explicitly opts out. The gem's
own `:boolean` caster answers `false` for a blank value; it is `Base`'s replacement caster and blank repair that make a
blank env variable read back as `true` here, not the gem's own default
behavior.

The design asked for one table rather than ten fields, because `RateLimitConfig`'s
`FLAG_FOR` already reads well and ten fields would duplicate it. The gem
binds one attribute per environment variable, so ten attributes is the only
shape that reads ten variables — but they exist only inside this settings
file. The one table keyed by scope stays exactly where it was, in
`RateLimitConfig`, still raising on an unknown scope.

## Why the typo guard reads the raw env value

The shared `:boolean` caster (`Base`) answers `false` for *any*
unrecognized non-blank text — deliberately, for the three other settings
groups that declare a `:boolean` and want "unreadable" to land on their safe
side without crashing boot (see `Base`'s comment on its `:boolean` registry
entry).

This group is the one place that shape is actually dangerous: every switch
here defaults to `true` (protected), so a caster-returned `false` is not
`nil`, `Base`'s blank repair never fires, and a one-letter typo (`"ture"`)
would switch a throttle off permanently with no error anywhere. The `on_load` hook that validates this reads the *raw* env
value, because by the time an `on_load` callback runs, the caster has already
thrown the original text away.

## Why the `preferences` scope is rate-limited by IP

`Users::PreferencesController#update` skips the usual cross-site request
check for callers using a bearer token, and skips sign-in entirely for the
anonymous signed-cookie path. The per-IP throttle on that scope is what
limits how often one IP address can hit that anonymous PATCH endpoint,
compensating for the two checks it does not get.

## Why the blank-repair spec builds a fresh settings instance per variable

`spec/lib/rate_limit_config_spec.rb`'s "blank repair, one per variable"
examples vary the raw `RATE_LIMIT_*` env variable rather than the setting,
because they are pinning what the declaration itself does with a blank
input, not what `RateLimitConfig.enabled?` reads.
`Sway::Settings.rate_limits` is memoized, so setting the env var
with `with_env` alone would never reach the new value through
`.enabled?` — the memoized instance was already built. Each example
instead calls `Sway::Settings::RateLimits.new` directly, sidestepping the
memoization entirely and proving the blank-repair behavior for all ten
kill-switch variables independently.
