---
mode: explanation
summary: "Why retiring an unproven LegislatorTerm deletes and rebuilds score rows in the same run, and what is lost when it doesn't."
status: agent-extracted
related: [docs/explanation/seed-legislator-terms-add-correct-retire.md, docs/explanation/score-recompute-service-overview.md]
---

# Why retiring a term rebuilds scores in the same run

`SeedLegislatorTerms#retire_unproven_terms!` deletes a stored
`LegislatorTerm` the published history does not know about. Only an
invented row can be in this position: for somebody with a complete
history, every term they really served is in the list.

## Deletion order

The score rows go first and the term second — the same order and the same
`delete_all` as `FinishMergingBaltimoreSeatRows#delete_row` — using
`delete_all` so no `after_commit` callback fires part way through a seed.
The score rows counted under an invented term have to go with it: they
count something that never happened, and `legislator_term_id` is `NOT
NULL`, so they cannot outlive it.

## Retirement restores the scores of the terms a person keeps

Retiring a term must also put back the score rows counted under the terms
this person KEEPS, because deleting scores for the retired term loses
`legislator_district_scores`, `legislator_locale_scores` and
`user_legislator_term_scores` rows that nothing else would restore.
`db:seed` runs on every container boot, so this fires whenever the roster
moves, not once — and the repair, `rails sway:scores:recompute_all`, runs
in no production path at all. Without the rebuild, a member whose invented
term was retired would show no score on the legislators page until somebody
ran it by hand.

## Why the rebuild happens here, not at the end of the deploy

Rebuilding at retirement time costs boot time only when a term was
actually retired, which is normally never. Rebuilding every legislator's
scores on every boot would cost that time every time, on a machine that
pays boot time before the health check.

## Why the "knows every table" spec is a tripwire, not a behavior test

`#retire_unproven_terms!` names three score tables by hand. Two of them
have no foreign key, and `delete_all` skips model callbacks, so a fourth
table added later that counts something under a `legislator_term_id`
would leave rows pointing at a term that no longer exists, with nothing
saying so. `seed_legislator_terms_spec.rb`'s "knows every table that
counts something under a term" example is not a behavior test — it walks
`ActiveRecord::Base.connection.tables` for any table carrying a
`legislator_term_id` column and asserts that set against the three tables
`#retire_unproven_terms!` names. It fails the day a fourth table is added,
which is the day somebody can still act on it, rather than the day a
production database quietly loses scores.

## Why the rebuild covers every remaining term, not just the current one

`rebuild_scores_for_remaining_terms!` puts back the score rows for EVERY
term this person still holds, not just the one running today. A term that
has ended is what the History tab reads, so leaving its rows missing is what
a reader sees. Rebuilding is free of side effects — `ScoreRecomputeService`
counts from `user_votes` and `legislator_votes` each time rather than adding
to what is there — so a run that changes nothing writes the same numbers
back.
