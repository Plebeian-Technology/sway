---
mode: explanation
summary: "Explains why bill score recomputation uses two separate callbacks instead of one on: [:create, :update] hook."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why score recompute uses two callbacks, not one

`Bill` queues an "interesting score" recompute from two separate callbacks:
`after_create_commit :enqueue_interesting_score_recompute_on_create` and
`after_commit :enqueue_interesting_score_recompute, on: :update`. This looks
like it could collapse into one `on: [:create, :update]` callback guarded by
`previously_new_record?`. It cannot, and the reason is a transaction timing
gotcha, not a style preference.

## Why creation needs its own trigger

A freshly fetched Baltimore bill with no vote, no organization position, and
no summary yet would otherwise get no score row until the next boot
backfill. That ranks it last in "Most Interesting" — for exactly the bills
an operator is most likely to be working on right now. Creation itself has
to count as a trigger.

## Why one combined callback does not work

`previously_new_record?` clears on the NEXT save after a record is created.
If a bill is created and then updated inside the same transaction, by the
time the transaction commits, that flag no longer shows "was a new record"
and the watched-field check does not see a change either. The row looks,
at commit time, like neither a new record nor a changed one — so a combined
callback queues nothing.

`after_create_commit` avoids this because it reads Rails' own transaction
bookkeeping about what happened, rather than a flag on the record that can
be overwritten by a later save in the same transaction. Two callbacks, under
different names, handle create and update correctly; one combined callback
silently drops the create-then-update case.

## Why the create hook needs its own method name

`enqueue_interesting_score_recompute_on_create` is a separate method that
just calls `enqueue_interesting_score_recompute`, rather than the create
callback pointing at the same method name the update callback uses. Two
`after_*_commit` callbacks registered under the same method name override
one another in Rails' callback chain — only the last one registered would
actually run. Two distinct method names is what lets both callbacks fire.

## Why repeated enqueues on the same bill are safe

`Bill#enqueue_legislator_vote_fetch` and
`Bill#enqueue_interesting_score_recompute` are called from `after_commit`
callbacks that can fire on unrelated saves in quick succession. Both are
safe to call redundantly: `LegislatorVoteFetchJob` and
`RecomputeBillInterestingScoreJob` each allow only one queued job per
`bill_id` and discard a duplicate rather than queuing a second one, so
several trigger-field changes in a row collapse into a single run rather
than piling up redundant work.

## LegislatorVote's bare after_commit callbacks

`LegislatorVote` registers two bare `after_commit` callbacks —
`:update_scores` and `:enqueue_interesting_score_recompute` — rather than
scoping either to `on: :update`. A bare `after_commit` fires on create,
update, AND destroy, which both callbacks need: `Legislator has_many
:legislator_votes, dependent: :destroy`, so reseeding or removing a
legislator cascades vote deletions across many bills. An earlier
`after_save_commit` version of `:update_scores` skipped the recompute on
destroy entirely. Without `:enqueue_interesting_score_recompute` also
firing on destroy, a bill score row's controversial/close signals would
keep reflecting votes that no longer exist.

The two callbacks use different method names
(`update_scores`/`enqueue_interesting_score_recompute`) for the same
reason `Bill`'s create and update hooks do above: two `after_*_commit`
callbacks registered under the same method name would override one
another in Rails' callback chain (`Rails/AfterCommitOverride`), so only
one would actually run.

`#update_scores` passes `legislator_id`, not the record, to
`OnLegislatorVoteUpdateScoresJob.perform_later` — a destroyed
`LegislatorVote` cannot be deserialized from a GlobalID, but
`legislator_id` stays readable after destroy. `bill_id` survives destroy
the same way, and `RecomputeBillInterestingScoreJob`'s own `Bill.find_by`
guards against the bill itself being gone by the time the job runs.

## Why transform_support_to_for_against_abstain has no else arm

`LegislatorVote#transform_support_to_for_against_abstain` normalizes known
support-value spellings (`"yea"`, `"aye"`, `"nay"`, and so on) and has no
`else` arm. An unrecognized value is left as-is on purpose, to be upcased
by `#upcase_support` and then rejected by the `inclusion` validation on
`support`. An earlier version had an `else s` arm, which was a dead
expression — assigning nothing — that read as if it did something.
