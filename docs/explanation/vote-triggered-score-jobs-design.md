---
mode: explanation
summary: "Why OnUserVoteUpdateScoresJob and OnLegislatorVoteUpdateScoresJob serialize per-key instead of discarding duplicates, and why the legislator job takes an id, recomputes from scratch, and only touches the current term."
status: agent-extracted
related: [score-recompute-service-overview]
---

<!-- vale Vale.Spelling = NO -->

# Why the vote-triggered score jobs serialize instead of discarding

`OnUserVoteUpdateScoresJob` runs at most one score recompute per bill at a
time (`limits_concurrency to: 1, key: "scores_bill_#{user_vote.bill_id}"`).
Without this, a recompute that already read the totals from before a new
vote landed could be thrown away, leaving stale totals saved.

Extra jobs wait their turn (Solid Queue's default) instead of being
dropped. That is on purpose and it differs from the rest of this repo,
which usually keeps one job and discards the rest. Correctness does not
depend on the choice — a recompute recalculates from scratch inside a
transaction — so this limit can be removed if it ever gets in the way.

`OnLegislatorVoteUpdateScoresJob` runs at most one score recompute per
legislator at a time, for the same reason, keyed on
`"scores_legislator_#{legislator_id}"`.

## Why `OnLegislatorVoteUpdateScoresJob` recomputes from scratch instead of applying deltas

An older version applied deltas instead. It wrote absolute single-bill
counts, so every ingestion flattened a legislator's whole accumulated
agreement history down to one bill's numbers, and it maintained a
`diff_count_*` store nothing ever read. `ScoreRecomputeService`
recalculates the real totals from source instead, so a second bill's vote
no longer erases the first, and a deleted vote needs no special handling —
the same recompute just runs with that row gone.

## Why it takes a `legislator_id`, not the `LegislatorVote` record

It takes a `legislator_id` rather than the `LegislatorVote` record so it
still works after the vote is deleted; Rails cannot turn a stored reference
back into a destroyed record. The recompute needs nothing beyond the
`legislator_id`, so passing `previous_support` or `bill_id` would add
nothing.

## Why only the legislator's current term is recomputed

It looks up the legislator's CURRENT term once and recomputes only that
term's rows. A vote ingested late — a departed member's recovered roll
call, or a sitting member's vote on a past term's bill — reaches no score
row from here: recomputing an ended term is unsafe until it is settled how
a departed member's constituents are counted. A
legislator with no current term — an executive, say, who is not scored by
term at all — makes this job do nothing.

## Why the recompute spec writes a deliberately wrong tally first

`spec/jobs/on_user_vote_update_scores_job_spec.rb`'s recompute example
seeds the bill's `BillScore` with a deliberately wrong tally before running
the job, then asserts the rebuild overwrites it with the number worked out
from `user_votes`. Asserting only that the job "does not raise" would still
pass if a change quietly broke the recompute and left the totals untouched
— checking that the totals are genuinely OVERWRITTEN is what actually
proves the recompute ran.
