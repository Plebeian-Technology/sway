---
lat:
  mode: explanation
---

# Why score recompute uses two callbacks, not one

`Bill` queues an "interesting score" recompute from two separate callbacks rather than one `on: [:create, :update]` hook. Transaction timing semantics prevent collapsing them into a single callback guarded by `previously_new_record?`.

## Why creation needs its own trigger

A freshly fetched bill with no vote, position, or summary yet would otherwise get no score row until the next boot backfill. That ranks it last in "Most Interesting", so creation itself has to count as a trigger.

## Why one combined callback does not work

`previously_new_record?` clears on the next save after record creation. If a bill is created and updated within the same transaction, that flag clears before commit time, so a combined callback queues nothing.

`after_create_commit` avoids this because it reads Rails' own transaction bookkeeping about what happened, rather than a flag on the record that can be overwritten by a later save in the same transaction. Two callbacks, under different names, handle create and update correctly; one combined callback silently drops the create-then-update case.

## Why the create hook needs its own method name

Two `after_*_commit` callbacks registered under the same method name override one another in Rails' callback chain. Two distinct method names ensure both callbacks fire rather than the last one replacing the earlier one.

`enqueue_interesting_score_recompute_on_create` is a separate method that calls `enqueue_interesting_score_recompute`, rather than pointing at the same method name the update callback uses.

## Why repeated enqueues on the same bill are safe

`LegislatorVoteFetchJob` and `RecomputeBillInterestingScoreJob` allow only one queued job per `bill_id`. Duplicate enqueues are discarded rather than queued again, collapsing rapid sequential changes into a single run.

## Bill trigger fields separate vote fetching from score recomputation

[[app/models/bill.rb#Bill#VOTE_TRIGGER_FIELDS]] and [[app/models/bill.rb#Bill#SCORE_TRIGGER_FIELDS]] watch different committed fields for vote fetching and interesting-score recalculation.

The two field lists serve different jobs. A locale move changes which theoretical maximum scores the bill against, so it belongs in the score list; it does not change the source roll call to fetch. Both lists use `after_commit` with `saved_change_to_attribute?` because each callback must run only after a committed update to its own inputs.

## LegislatorVote's bare after_commit callbacks

`LegislatorVote` registers bare `after_commit` callbacks for `:update_scores` and `:enqueue_interesting_score_recompute` so they fire on create, update, and destroy. Reseeding or removing a legislator cascades vote deletions across many bills.

An earlier `after_save_commit` version of `:update_scores` skipped the recompute on destroy entirely. Without `:enqueue_interesting_score_recompute` also firing on destroy, a bill score row's controversial/close signals would keep reflecting votes that no longer exist.

The two callbacks use different method names (`update_scores` and `enqueue_interesting_score_recompute`) because two `after_*_commit` callbacks registered under the same method name would override one another in Rails' callback chain (`Rails/AfterCommitOverride`).

`#update_scores` passes `legislator_id`, not the record, to `OnLegislatorVoteUpdateScoresJob.perform_later` — a destroyed `LegislatorVote` cannot be deserialized from a GlobalID, but `legislator_id` stays readable after destroy. `bill_id` survives destroy the same way, and `RecomputeBillInterestingScoreJob`'s own `Bill.find_by` guards against the bill itself being gone by the time the job runs.

## Why transform_support_to_for_against_abstain has no else arm

`LegislatorVote#transform_support_to_for_against_abstain` normalizes known support spellings and omits an `else` branch on purpose. Unrecognized values remain untouched to be upcased and rejected by the `inclusion` validation on `support`.

An earlier version had an `else s` arm, which was a dead expression assigning nothing that read as if it did something.
