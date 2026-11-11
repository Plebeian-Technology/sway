---
mode: explanation
summary: "Explains why serialize_entry stringifies payload keys once and why for_flash mode replaces the raw LLM response with a pointer."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why serialize_entry works the way it does

`PipelineActivityLogger.serialize_entry` turns one entry into the hash
that goes out to the browser. It is public because the code that loads
the Activity Log page sends the same shape. `created_at` must keep
microsecond precision.

## Why `created_at` is written with `iso8601(6)`, not plain `iso8601`

`PipelineActivityLogger` writes `created_at` with `iso8601(6)`, keeping
six digits after the seconds, so paging through entries by timestamp keeps
them in order even when several are written within the same second. Plain
`iso8601` records whole seconds only, so entries sharing a second would
collide in the paging sort — indistinguishable by timestamp alone, in
whatever order the query happened to return them.

The shared examples `"emits microsecond-precision timestamps"`
(`spec/support/shared_examples/microsecond_precision_timestamps.rb`) pin
this down for any spec that extends the logger:

```ruby
include_examples "emits microsecond-precision timestamps",
  emit: -> { PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil) }
```

The `emit` lambda must return the saved entry (an `ActivityLogEntry`); its
`serialize_entry` output is what gets inspected. A failure here means a
refactor quietly dropped back to plain `iso8601`.

## Stringifying payload keys once

The payload's keys are forced to strings at this one point, where every
delivery path passes through.

Before the record makes a round trip to the database, the hash still has
symbol keys, exactly as the payload object built it. Once it has been
stored and read back as JSON, the keys are strings. An earlier version
trimmed the raw response by checking only for the string key, so the trim
quietly did nothing on the after-commit path, where the symbol keys
survive. Converting keys to strings once here means everything downstream
sees the same shape, regardless of which path the entry took to get here.

## Why `dispatch_inertia` writes into the flash

The request is about to render a page, so `Transport.dispatch_inertia`
tucks the entry into the flash. `ApplicationController` shares the flash
with React on every response, so it arrives with the page.

## Dropping the raw response for flash

`for_flash` mode drops the raw model response, which can run to 4000
characters, and replaces it with a note saying where to find it. The
flash travels in a session cookie, and cookies cap out around 4KB. The
WebSocket path has no such limit, so it keeps everything.
