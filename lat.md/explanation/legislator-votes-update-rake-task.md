---
lat:
  mode: explanation
---

# Legislator-votes update rake task

The `sway:legislator_votes:update` rake task is the manual, ops-triggered counterpart to [[app/jobs/legislator_vote_sweep_job.rb#LegislatorVoteSweepJob]]'s daily run, refreshing legislator votes per bill across locales.

## Locale argument

The locale argument accepts the full "city-state-country" format parsed by [[app/models/sway_locale.rb|find_by_name_parts]], defaulting to every bill across all locales when omitted.

## Why run_service_for, not perform_now

The task calls [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob#run_service_for]] rather than `perform_now` to bypass ActiveJob retry handlers, allowing upstream errors to reach the circuit breaker.

Calling the class method directly lets errors from upstream escape rather than being quietly requeued, enabling the task's loop to catch them, track error streaks, and break early during prolonged outages.

## force_refresh removal

The legacy `force_refresh` parameter was eliminated end-to-end: the rake task no longer passes it and [[app/jobs/legislator_vote_fetch_job.rb#LegislatorVoteFetchJob#run_service_for]] no longer accepts it.

## Circuit breaker and permanent refusals

Permanent per-bill refusals such as [[app/scraper/scraper/congress/roll_call_not_on_the_bill.rb#RollCallNotOnTheBill]] are logged and skipped without tripping the three-consecutive-errors circuit breaker or failing the run.

A dedicated rescue clause placed before the general rescue catches classified permanent refusals—including [[app/scraper/scraper/congress/roll_call_not_on_the_bill.rb#RollCallNotOnTheBill]] and [[app/scraper/scraper/congress/roll_call_mismatch.rb#RollCallMismatch]]—appending them to a skipped collection while leaving the streak counter untouched. A genuine upstream outage produces transport or client errors caught by the general rescue, which advances the streak counter and exits with a non-zero status upon reaching three consecutive failures.

Unclassified exceptions and [[app/scraper/scraper/congress/roll_call_unavailable.rb#RollCallUnavailable]] fall through to the general rescue by design. An unfetchable roll call represents an operational data acquisition failure rather than a permanent per-bill mismatch. Treating [[app/scraper/scraper/congress/roll_call_unavailable.rb#RollCallUnavailable]] as a potential outage increments the consecutive error counter and halts execution after three consecutive failures, protecting the system against hammering unavailable upstream APIs across thousands of records. When a run completes with only permanent per-bill refusals, it exits with status zero because permanent skips represent expected data variance rather than operational failure.

When Senate fallback fetches occur during batch sweeps, [[app/scraper/scraper/congress/senate/legislator_votes.rb#LegislatorVotes]] caches the Voteview roll-call index in `Rails.cache` for six hours. The cache entry stores only compact three-key hashes (`session`, `clerk_rollnumber`, `rollnumber`) to minimise memory overhead across large batch runs. A fifteen-minute freshness window suppresses repeated network requests for missing roll calls: if an index lookup misses but the index was fetched within the last fifteen minutes, the scraper logs the missing vote and avoids re-requesting the upstream index on subsequent bills in the same sweep.

## Upserter write guard rules

Guessed sponsor votes never overwrite real recorded votes, and automated service writes never overwrite manual admin edits.

An incoming vote marked `inferred: true` cannot overwrite an existing row where `inferred` is false. Admin writes stamped as manual are protected from automated updater sweeps, preserving operator corrections.
