---
mode: explanation
summary: "Explains the sway:legislator_votes:update rake task's locale lookup, why it dispatches via run_service_for instead of perform_now, and the removed force_refresh argument."
status: agent-extracted
related: [docs/explanation/legislator-vote-sweep-design.md]
---
# sway:legislator_votes:update rake task

<!-- vale Vale.Spelling = NO -->

The `sway:legislator_votes:update[locale_name]` rake task is the manual,
ops-triggered counterpart to `LegislatorVoteSweepJob`'s daily run.

## Locale argument

The locale argument is the full "city-state-country" name, looked up with
`SwayLocale.get_by_name`, the same way `lib/tasks/reset_legislator_photo_urls.rake`
does it. With no argument, the task iterates every `Bill` across every
`SwayLocale`.

## Why run_service_for, not perform_now

The task calls `LegislatorVoteFetchJob.run_service_for`, not `perform_now`,
because `perform_now` runs the job's `retry_on` and `rescue_from` handlers.
A retryable error such as `Legistar::Client::Error` would then be quietly put
back on the queue and never reach the task's own rescue, which records the
failure and moves to the next bill, or its stop-after-three-errors-in-a-row
circuit breaker. Calling the class method directly lets errors from upstream
escape, which is why the task's spec raises the error Baltimore really
produces (`Legistar::Client::Error`) to prove the breaker counts it.

## force_refresh removal

`force_refresh` is gone from end to end: the task no longer passes it and
`run_service_for` no longer accepts it.
