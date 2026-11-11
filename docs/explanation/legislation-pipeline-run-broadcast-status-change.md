---
mode: explanation
summary: "Explains why LegislationPipelineRun#broadcast_status_change is a shared extracted method, sends event: nil, includes error_message, and routes through PipelineRunBroadcast."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why LegislationPipelineRun#broadcast_status_change is built this way

`#broadcast_status_change` is the one message every status change sends.
It is extracted so the `after_commit` hook and `#reopen_stuck_stage!`
cannot describe the same event two different ways.

## Why event: nil

The frontend hook `usePipelineRunSubscription` only calls
`router.reload({ only: [...] })` when a message arrives — it never reads
`event` from the payload. If a future subscriber needs the event name,
switch to thread-local propagation instead.

## Why error_message rides along

Including `error_message` lets cable subscribers see the failure reason at
the same instant they see the status change. Before, a subscriber learned
the run failed but had to wait for the next `router.reload` poll to see
why — a briefly inconsistent view on the operator screen. `error_message`
is truncated to 500 characters in `handle_run_failure`
(`run_legislation_pipeline_job.rb`), so the cable payload stays bounded.

## Why it goes through PipelineRunBroadcast

The send goes via `PipelineRunBroadcast.deliver` so a failed send cannot
fail the run.

## Why PipelineRunBroadcast.deliver never lets a failure propagate

An exception raised in an `after_commit` callback travels back to whoever
saved the record, and `RunLegislationPipelineJob` turns that into a failed
run. So a run doing real work used to be thrown away because a status
message could not be delivered.

Dropping a message is cheap: every screen that reads these also polls, so
it fixes itself within seconds. There is no way to get a destroyed run
back — that asymmetry is why `#deliver` rescues broadly and returns `false`
rather than letting the broadcast failure become the caller's failure.

`log_event` lets each caller keep its own name in the log, so a failure at
one call site is not confused with a failure at another. `SwayLogging.log_exception`
only reaches `Rails.logger`, so without a second report a bus that is down
for a week looks like a week with nothing to send — the `Sentry.capture_exception`
call is unguarded because sentry-rails is deliberately not production-only;
with no DSN it no-ops.

Every caller that reaches `PipelineActivityLogger::Transport.dispatch_async`
shares this one seam rather than writing its own rescue, so a
fourth sender cannot be added without the same guard.

## Why the after_commit hook is separate and gated on saved_change_to_status?

The broadcast lives in its own `after_commit on: :update` hook, rather than
inside the state machine's transition callbacks, so subscribers never see a
status that later rolls back — `after_commit` only fires once the
transaction that changed it has actually landed.

The `saved_change_to_status?` gate keeps a write that touches some other
column — `update_columns(error_message: "x")`, or
`update_columns(current_stage: "extract-text")` — from triggering a
broadcast for no reason: those calls change what a subscriber would read on
the next poll, but not the state a status broadcast exists to announce.
