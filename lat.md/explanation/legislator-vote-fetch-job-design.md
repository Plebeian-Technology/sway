---
lat:
  mode: explanation
---

# Why LegislatorVoteFetchJob is shaped the way it is

`LegislatorVoteFetchJob` fetches legislator votes for one bill, dispatching to the right service for the bill's locale.

It is invoked from three places: `Vote#after_create` (the Baltimore/`local?` branch), `Bill#after_commit` on update for the fields whitelisted as vote triggers, and `LegislatorVoteSweepJob`'s daily full sweep. It is safe to run more than once (idempotent), and runs are coalesced per `bill_id`: duplicate enqueues for the same bill are discarded, NOT queued behind each other.

`:polynomially_longer` is the retry symbol Rails actually defines (see Rails PR #49292 and the `mirror_external_asset_job.rb` precedent). An earlier planning doc named a different symbol that does not exist in Rails.

## Why the retry list is narrow

Keep the retry list narrow so permanent errors (`ArgumentError`, `NoMethodError` from a malformed upstream payload) are not retried against the same bill — they cannot succeed and they multiply upstream HTTP load.

Discard known-permanent failure classes outright (`discard_on ActiveRecord::RecordNotFound, ArgumentError`); retry only true transport/transient classes, 3 attempts each. Anything else propagates to `ApplicationJob`'s terminal Sentry capture.

The old `LegislationClient` is gone; the retry list names only network errors raised by Faraday/Net directly — plus one wrapper class: `Legistar::Client#get` rescues `Faraday::Error` — which includes `Faraday::TimeoutError` and `Faraday::ConnectionFailed` — and re-raises EVERYTHING as `Legistar::Client::Error`, so the two Faraday classes can never escape the client on the Baltimore path. Without the wrapper class in the retry list, every transient Legistar 503/timeout was a terminal job failure instead of a retry. `Legistar::Client::HttpError` (non-2xx) subclasses `Error` and is therefore retried too — 5xx is the common transient case, and a retry of a non-transient 4xx is bounded at 3 attempts.

## Why service_class_for has no fallback arm

`service_class_for` turns a declared `vote_source` name into the service that reads that source. It's a method rather than a constant hash, so the class is looked up when a bill is dispatched rather than when this file loads.

There is no fallback arm. This used to ask the locale which KIND it was, so every city landed on the Baltimore service — which then asks Legistar's own default jurisdiction, Baltimore, for whatever matter number the bill carries. A second city's bill would have collected Baltimore's dates.

## Why run_service_for exists as a shared class method

`run_service_for` is shared synchronous dispatch, used by both `#perform` and `lib/tasks/sway_legislator_votes.rake`. See [[docs/explanation/legislator-votes-update-rake-task.md|the rake task's own doc]] for why the rake task must call this instead of `perform_now`.

`force_refresh` is NOT forwarded to any of the vote services — the service rewrite made every Baltimore run a live Legistar lookup, so the cache-bypass kwarg was removed from the service. No caller passes `force_refresh` anymore either (see below for why `#perform`'s kwarg is still accepted).

## Why perform still accepts force_refresh: as a no-op

`force_refresh` is a retained NO-OP.

The disk cache it once bypassed was deleted along with the rest of the Python sidecar, and no caller passes it anymore (the sweep and the rake task both stopped). The kwarg is kept ONLY so a deploy cannot break jobs already in the queue: a job serialized with `force_refresh: true` by the previous version of the code must not raise `ArgumentError` on deserialization — `discard_on ArgumentError` above would silently discard it. Safe to drop in a later phase once no such jobs can remain queued.

## Why the retry-vs-discard spec checks behavior, not registration

`spec/jobs/legislator_vote_fetch_job_spec.rb` asserts that a `Legistar::Client::Error` actually causes a re-enqueue, rather than merely asserting that the class appears in `retry_on`.

`rescue_handlers` lists `retry_on` and `discard_on` entries the same way, so a check that only looks for the class name in that list would stay green even if a later edit moved the class to `discard_on` — quietly turning every passing Legistar failure into a silently discarded job instead of a retried one. Driving the job with `perform_now` and observing that it re-raises (rather than swallowing the error) is what actually distinguishes the two outcomes. That same swallow-then-re-enqueue behavior of `perform_now` is why the rake task has to call `run_service_for` instead — see [[docs/explanation/legislator-votes-update-rake-task.md|the rake task's own doc]].

## Why the no-declaration case refuses outright

Before dispatch read the locale's DECLARED vote source, "neither Congress nor a state" WAS the Baltimore branch: a second city's bill fell through to the Baltimore service, which asked Legistar's own default jurisdiction.

Before dispatch read the locale's DECLARED vote source, "neither Congress nor a state" WAS the Baltimore branch: a second city's bill fell through to the Baltimore service, which asked Legistar's own default jurisdiction — Baltimore — for whatever matter number the bill happened to carry. Nothing raised, nothing showed on screen, and the date written onto the bill was another city's. `service_class_for`'s missing fallback arm (above) is the fix; a bill whose locale has no vote-source declaration now raises `SwayLocale::JurisdictionRules::Undeclared` instead of silently borrowing Baltimore's answer.

## Why the interim defined?(BaltimoreLegislatorVoteUpdateService) guard was removed

An earlier version of the job carried a guard for the gap between two deploys: a `defined?(BaltimoreLegislatorVoteUpdateService)` check that logged a warning and did nothing if the class wasn't loaded yet.

That guard has since been deleted — the service shipped long ago and has since been rewritten, so the guard could never actually run, and its warning message no longer described anything true.

## Why the whitelisted-field spec picks its replacement values carefully

`bill_spec.rb`'s whitelisted-field examples change one whitelisted field at a time on a bill and assert the job enqueues exactly once.

Every replacement value has to be one the schema accepts: `status` must come from `Bill::STATUSES` (`passed`, `failed`, `committee`, or `vetoed`) and never a random `"changed-#{rand}"` string, because `Bill#downcase_status` turns an unknown status into `nil`, the presence validation then rejects the record, and the `after_commit` callback under test never runs — a random string would make the example pass for the wrong reason (or not run the callback at all) rather than actually exercising the whitelist. `alternate_status_for` picks any status different from the fixture's starting `"committee"`, and `alternate_chamber_for` does the same for `chamber` (the factory default is `"council"`, and the model accepts `house`/`senate`/`council`).
