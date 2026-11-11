---
mode: explanation
summary: "Why with_env exists as one shared helper, and the Ruby ENV assignment behavior that made five earlier copies harmless despite disagreeing."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `with_env` is one helper

`with_env` (`spec/support/env_helpers.rb`) sets environment variables for
the length of one example, then puts back exactly what was there.

The same method was written five times, in five spec files, in three
spellings. Nothing made them agree, and one had already drifted: it
assigned without a nil guard while the other four branched on nil.

## The drift turned out to be harmless

That drift is worth recording because it is the kind of claim that gets
repeated without being run: `ENV[k] = nil` does NOT raise in Ruby — it
deletes the key, which is what the four guarded copies did by hand. Measured
on Ruby 4.0.7. A `TypeError` comes only from a value that is neither a
`String` nor `nil` (an `Integer`, say), and every copy shared that
assumption. So five copies were five chances to drift rather than one live
defect.

## Why `with_app_config` joins `with_env` rather than replacing it

`with_app_config` swaps a whole `Sway::Settings` group instance rather than
changing `ENV` directly, because a spec that varies a setting already
migrated to `Sway::Settings` needs that: the memoized reader on the group
instance never re-reads `ENV`, so `with_env` alone would not move it.
`with_env` still exists alongside it, for a credential or one of the
settings that cannot move onto `Sway::Settings` at all.

## Why a file-wide `with_app_config` swap needs `around`, not `before`

`with_app_config` (also in `spec/support/env_helpers.rb`) must yield to the
example body and restore the previous group instance afterward — a `before`
hook cannot wrap example execution the way that block needs to. When a spec
file needs the same config override for every example in the file, the
correct shape is:

```ruby
around do |example|
  with_app_config(:llm, llm_provider: "claude") { example.run }
end
```

This is the same pattern used across the LLM job specs (see
`spec/jobs/backfill_bill_categories_job_spec.rb`) for a before/after swap
spanning a whole file.

## Why `generate_bill_summary_job_spec.rb` uses `stub_app_config` plus a file-wide `after`, not `with_app_config`

`stub_app_config` installs a settings group instance directly, with no
block to scope the swap to — the shape this file's many one-line
`stub_const("ENV", ...)` calls already had, where dozens of examples vary
exactly one call-time value at the very top of an `it` or `before`, with no
natural block for `with_app_config`'s swap to live inside. A single
`after { Sway::Settings.reset! }` at the top of the file restores every
group to a fresh, real-ENV-backed instance once each example ends,
mirroring the auto-teardown `stub_const` itself provides.
