---
mode: explanation
summary: "Why BootStep exists to report and re-raise a boot-time failure, and the Kamal health-check timeout it works around."
status: agent-extracted
related: [docs/explanation/queue-schema-regeneration-risk.md]
---

# Why BootStep exists

`BootStep` runs one of the database steps a container performs before it
serves anything, and makes sure a failure is heard.

## The problem it works around

Kamal reports a crash in one of these steps as "target failed to become
healthy within configured timeout (10m0s)" — ten minutes of nothing, with
the real error left in a container that is crash-looping. Nothing else
catches it: the error service watches requests and jobs, and a rake task
raising on the way up is neither. That shape already cost four deploy
cycles.

## Report, then re-raise

A boot step that failed must still fail the boot; the only thing that
changes is that somebody is told why.

## Where the report goes

Where the report goes is decided by `config/initializers/sentry.rb`, not
`BootStep` itself: production sends to the error service, development and
test send to the collector on the machine, and an environment with
neither drops it. So this never sends a developer's seed failures anywhere
off their own machine.

## Why `.report` is safe to call even when Sentry never started

Sentry hands back nil when it was never initialized, so `Sentry.capture_exception`
here is a no-op rather than a second failure on top of the first.

Nothing flushes here on purpose: `Sentry.init` registers `at_exit { close }`
itself, and `close` flushes — read from sentry-ruby 6.7.0, not assumed. A
second close would work and would also switch every later report off.
