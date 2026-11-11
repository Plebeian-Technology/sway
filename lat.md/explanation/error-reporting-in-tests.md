---
lat:
  mode: explanation
---
# Error reporting during a test run

A spec run sends the errors the application raised to a local collector, the same way production sends them to a remote one. That client is live while examples run, which shapes how a spec is allowed to observe it.

## Why Sentry's methods are watched rather than the constant replaced

An example that needs to see a report stubs `Sentry.capture_exception` or `Sentry.capture_message` on the real constant instead of putting a double in its place.

`sentry-rails` installs `Sentry::Rack::CaptureExceptions` and subscribes to
Rails' own notifications, and a test run starts a real client, so the framework
itself calls into `Sentry` while an example is running — on the first `create`
inside an example, and on every request. A double standing in for the whole
constant meets those calls, cannot answer them, and the example dies somewhere
unrelated to what it was testing. Stubbing one method leaves the rest of the
constant intact, so the framework's own calls still land where they always did.

The gems used to sit in the production-only bundle group, which is why older
examples got away with replacing the constant and why the branch guarded by
`defined?(Sentry)` used to be dead outside production. They load in every
environment now, so both of those changed at once.

## Why the reporting gems are not production-only

`sentry-ruby` and `sentry-rails` are declared outside every bundle group, because development and test report to a local collector speaking the same protocol a hosted one does.

Loading everywhere also removes a class of bug the production-only grouping
created: a rescue block that reported the error it had caught raised
`NameError` instead, because the constant it called did not exist in the
environment the code was running in. The failure landed on the error path, so
it surfaced only once something else had already gone wrong.

## What a test run reports, and what it leaves alone

`ReportApplicationErrors` reports an error that escaped into an example, tagged with the test that produced it, and says nothing about a failed expectation.

Getting it wrong costs in both directions. Reporting failed expectations would
flood the collector with the ordinary output of a red suite, and reporting
nothing would let a real application error pass for an ordinary test failure.
The harness captures its Sentry handle once, before any example can replace it,
so a spec that stubs the constant cannot make the harness answer to its double
and fail the example it was helping.

## Where a browser's error reports go during a spec run

The address the browser uses is not the one the project file records: under `dip run rspec` Chromium runs inside the container, where `localhost` is the container itself.

`VITE_RUSTRAK_DSN` therefore names the collector by its compose service name,
and the file is the fallback for a run started by hand on the host. The
collector is not load-bearing either way — both SDKs no-op without an address,
so a collector that is down changes nothing except that an example which would
have reported reports nothing. Which lanes can and cannot reach it is recorded
in [[verification-gates#Known traps]].

## Why the collector's own database is a named volume

The collector keeps what an error was carrying, so its SQLite file holds copies of request bodies and parameters from a development or test run.

A bind mount would put that file inside the checkout, where it can be committed
or swept into a repository backup. A named volume keeps it out of every tree
that is ever published. The collector itself scrubs nothing on ingest; the
scrubbing happens on the way out, in the browser's `beforeSend` and in
`config/initializers/sentry.rb`.
