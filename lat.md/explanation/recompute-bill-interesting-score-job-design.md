---
lat:
  mode: explanation
---

# Why RecomputeBillInterestingScoreJob is shaped the way it is

`RecomputeBillInterestingScoreJob` is a small dispatcher: given one bill, recompute its "interesting" score with `BillInterestingScoreCalculator`.

## Why there is no recurring schedule

It runs only from event triggers.

It runs only from event triggers — callbacks on `LegislatorVote`, `OrganizationBillPosition` and `Bill`, the summarization hook, and `ReplaceBillOrgPositionsService`, which enqueues by hand ON TOP OF the callbacks its own `save!` calls already fire. That path writes with `save!` and `update!`, not `insert_all!`, so no callback is skipped there; coalescing (below) is what keeps the extra enqueues cheap. There is deliberately no schedule for this job in `config/recurring.yml`. That absence is a hard requirement, not an oversight.

## Why jobs coalesce per bill with discard, not a queue

Jobs are coalesced per bill: only one may run at a time for a given `bill_id`, and extra enqueues are dropped (`on_conflict: :discard`), the same pattern `LegislatorVoteFetchJob` follows.

A burst of triggers on one bill — say several `LegislatorVote` upserts from a single ingestion sweep — collapses into one recompute instead of a queue full of duplicates.

## The known cost of dropping duplicates

The lock is held until a running job FINISHES, so triggers that commit while a recompute is already in flight (the tail of an ingestion burst) get dropped, and the saved score reflects only part of the vote set.

That is the accepted tradeoff of drop-style coalescing, not a bug in the triggers. The daily `LegislatorVoteSweepJob` re-runs the locale services, and their upserts fire `after_commit` even when nothing actually changed, which re-triggers a recompute for every swept bill — so a stale score never lasts more than about 24 hours.

## Why there is no retry_on or discard_on

`BillInterestingScoreCalculator` only touches the database, with no outside HTTP or API calls, so there is no flaky kind of failure worth retrying. `BackfillBillCategoriesJob` keeps the same narrow policy.
