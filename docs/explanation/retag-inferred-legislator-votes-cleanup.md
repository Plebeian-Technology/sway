---
mode: explanation
summary: "Explains why RetagInferredLegislatorVotesJob exists, which synthetic vote rows it retags, and why its score recompute is delayed to avoid racing an in-flight recompute."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why RetagInferredLegislatorVotesJob exists and how it's paced

`RetagInferredLegislatorVotesJob` is a one-off cleanup that marks old
synthetic legislator votes as inferred. It's enqueued on every boot by
`config/initializers/retag_inferred_legislator_votes.rb`, the same
mechanism `config/initializers/backfill_bill_interesting_scores.rb` uses.

## Why it exists

When a bill has no real roll call, Sway fills in votes by assuming its
sponsors voted FOR. Those synthetic rows have existed for a long time, but
the `inferred` flag column arrived much later (migration
`20260701000002`), and nothing backfilled it, so every older synthetic row
is still stored as `inferred: false`. The scoring engine — which reads
`where(inferred: false)` — counts it as a real recorded vote. That invents
"defection" and "close margin" signals that never happened.

The daily `LegislatorVoteSweepJob` can't fix this on its own:
`LegislatorVoteUpserter` refuses to overwrite a real vote with an inferred
one (`return false if inferred && !existing.inferred`), and these old rows
look real to it, so the flag never gets re-stamped. Without this cleanup
job the mislabeling is permanent.

## What it touches

Only rows that could not possibly be real data:

1. **Baltimore**: every `source: "legistar"` row is inferred by
   construction. Baltimore's Legistar feed publishes 0 of 200 real
   per-member roll calls, so `infer_from_sponsors` is the only code path
   that can write a per-legislator row for it.
2. **Congress and Maryland**: a row marked `inferred: false, support: FOR`
   on a bill with no `Vote` row holding a house or senate roll-call number
   has to be synthetic — the real scrapers only run when handed a
   roll-call number, so they could never have produced it.

The job is safe to run repeatedly: after the first run both queries match
zero rows, because every new inference write already sets `inferred:
true`. Later boots just pay for two cheap no-op queries. Rows entered by
hand (`source: "manual"`) are never touched by either query.

Baltimore scores don't need a recompute after this retag — the
calculator's Baltimore branch (`local_signals`) never reads
`legislator_votes`, so Baltimore scores were never affected by the
mislabeling.

## Why the Congress/Maryland recompute is delayed 30 seconds

The retag uses `update_all`, which writes straight to the database and
skips ActiveRecord callbacks — `LegislatorVote`'s `after_commit` recompute
trigger never fires. `RecomputeBillInterestingScoreJob` is enqueued by hand
instead, because the retag changes what the calculator's
`where(inferred: false)` query sees.

The delay itself is deliberate, not incidental. Recompute jobs are
coalesced per bill and extra ones are dropped
(`on_conflict: :discard`), and Solid Queue only checks that coalescing rule
when a job comes due. Enqueuing immediately could race a recompute that
started *before* this cleanup: the new job would be dropped, and the stale
score would stick. These particular bills — Congress and Maryland ones
with no roll-call number — are exactly what the daily sweep filters out,
so the usual ~24h self-heal would never rescue them either.

After a 30-second wait, any recompute that was still running has finished
and released its concurrency slot. A drop at that point means a recompute
started *after* this `update_all` committed — it already read the
corrected rows, so dropping it is harmless.

## Why the boot initializer needs no duplicate guard of its own

`config/initializers/retag_inferred_legislator_votes.rb` runs in BOTH boot
processes — the Puma web server and the separate `bin/jobs` background
worker — so every deploy enqueues the job at least twice. The job declares
`limits_concurrency to: 1, key: "retag_inferred_legislator_votes"`, which
folds simultaneous enqueues into a single run, so the initializer itself
does not need its own duplicate-boot guard.

The enqueue is wrapped in a rescue that names the errors it expects
(`ActiveRecord::ConnectionNotEstablished`, `ActiveRecord::NoDatabaseError`,
`ActiveRecord::StatementInvalid`, `SolidQueue::Job::EnqueueError`), because
on a fresh container the database connection may not be ready yet. A failed
enqueue at boot must not take the whole app down; the next boot tries
again. A bare `rescue` is deliberately avoided there — it would hide real
bugs at boot.
