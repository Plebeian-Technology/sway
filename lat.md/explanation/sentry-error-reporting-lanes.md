---
lat:
  mode: explanation
---

# How errors reach Sentry in production

Errors reach Sentry through two lanes.

- **Per-row errors are reported explicitly.** Each service that maps a
  single data row wraps that row in its own narrow rescue block and calls
  `Sentry.capture_exception` itself.
- **Network and upstream errors bubble up to the background job.**
  `sentry-rails` auto-captures those only when the job finally gives up —
  after all 5 `retry_on` attempts, or inside a `discard_on` block. One root
  cause therefore produces one Sentry event, not one per retry.

`config.rails.active_job_report_on_retry_error` in `config/initializers/sentry.rb` controls the second lane. Setting it `true` would report every retry: `sentry-rails` subscribes to the "retry enqueued" notification, so a transient error that clears on attempt 4 would emit three events for a job that never actually failed. Leaving it `false` waits for the terminal failure instead.

This is also the gem's own default, and the codebase sets it explicitly so the next reader sees a decision rather than an omission. An earlier comment here described the direction backwards; the current direction was verified directly in the installed `sentry-rails` 6.6.2 source — `configuration.rb:195` defaults the flag to `false`, and `active_job.rb`'s retry handler reports only when the flag is `true`.

## Why the trace/profile sample rate is 10%, not a traces_sampler

Production runs on a single arm64 Raspberry Pi.

Tracing and profiling every request is real overhead there (stackprof ships in the Gemfile), so `config/initializers/sentry.rb` samples only 10% (`config.traces_sample_rate = 0.1`, `config.profiles_sample_rate = 0.1`).

Do not add a `traces_sampler` lambda: it silently overrides `traces_sample_rate` — one used to live here and forced 100% tracing.

## Why spec/config/sentry_initializer_spec.rb requires sentry-ruby/sentry-rails by hand

`sentry-ruby` and `sentry-rails` sit in the Gemfile's `production` bundler group, so under `bundle exec` they are on the load path, but Bundler never `require`s them in the `test` environment.

The spec requires both by hand at the top of the file, the same way `spec/lib/env_secret_call_sites_spec.rb` requires `newrelic_rpm` to pin down the behavior of a production-only gem.

## Why the initializer is loaded and run, not just read as a comment

`config/initializers/sentry.rb` only runs when `Rails.env.production?`, which is exactly how its contents once drifted away from a comment describing them, with nothing noticing: no test had ever run that block.

So the spec runs it. `Sentry.init` is stubbed to yield a real `Sentry::Configuration` (it never touches the network or the DSN), the initializer is `load`ed with `Rails.env` forced to `"production"`, and the examples check the `Configuration` object that comes back. That turns the settings production truly runs with into something a test can look at, instead of a comment a reader has to trust.
