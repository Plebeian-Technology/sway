---
mode: explanation
summary: "Explains the shared rule that every gate settling a bill-summary row to a non-completed status must first check for an operator's pasted summary."
status: agent-extracted
related: []
---
# The deferred paste hand-off rule

<!-- vale Vale.Spelling = NO -->

`GenerateBillSummaryJob#finish_deferred_paste!` answers the one question
every gate that moves a provisioning row to a terminal status other than
`completed` has to ask first: does a human own the body on this row?

`#settle_completed` is the exception, and the only one, because
`completed` is where a hand-off ends anyway — it cannot strand one. The
rule reads "every gate," so a reader checking whether it was kept found
one of the five sites breaking it, and a sixth gate settling to
`completed` would have taken a second lock to ask a question with one
answer.

## Why the rule exists

`PasteSummaryService` declines to settle a `pending` or `generating` row
and logs that a queued or running `GenerateBillSummaryJob` owns its
status and will settle it. Whoever gets to the row next is that job, and
`skipped` and `failed` are terminal AND outside
`BillLlmProvisioning#reclaimable?` — so a gate that settles on the status
alone drops the hand-off for good, with every route back shut at once:
`#settle_superseded_row` and `SummaryRunArmDecision`'s `:paste_hand_off`
both need a non-terminal status, and `ReclaimAbandonedSummaryRunsJob`
needs `#reclaimable?`. The operator's hand-written summary would then sit
under a "Skipped" or "Failed" badge for good, and the only way off it
destroys the paste.

## Four gates, one rule

An earlier fix closed this shape at the sweep, and a later review found it surviving at
the stale-job gate, which runs before the supersede gate; the two
no-summary settles (see
[bill-summary-nothing-to-generate-settlement.md](bill-summary-nothing-to-generate-settlement.md))
and `#record_failure` (see
[bill-summary-failure-logging.md](bill-summary-failure-logging.md)) own
the window AFTER the paid region, which every stand-down in `#perform`
runs before. Each site was correct on its own and wrong one branch over,
which is what a shared reader — `#finish_deferred_paste!` — is for. A
fifth gate has to come through here.

### The narrowest of these windows: Arm 2's own no-summary settle

Of the gates that review routed through `#finish_deferred_paste!`, Arm 2's
no-summary settle (testimony present, no bill text — see
[bill-summary-nothing-to-generate-settlement.md](bill-summary-nothing-to-generate-settlement.md))
opens the narrowest window of them all: between the positions persist's
own lock committing and this settle's own lock. A paste landing there is
the easiest of the four to miss in a future edit, precisely because the
window is so small — which is exactly why it needs its own spec rather
than relying on the shared reader being exercised by the other three. The
paste is landed from the settle's own log line
(`generate_bill_summary.positions_only_no_summary`), the same technique
the `nothing_to_generate` example uses for Arm 1. Without the shared
reader here, the row would be marked `failed` under the operator's own
hand-written summary, with every route back shut — `failed` is terminal
and outside `#reclaimable?`.

## Calling convention

Callers must be inside `#settle_under_lock`, so `provisioning` is
committed state under the write lock and the hand-off's own transitions
join the same transaction. A truthy answer means the row is settled and
the caller must not settle it again.

## settle_superseded_row: why the whole hand-off runs in one lock

This used to take two locks: the first moved `pending -> generating`, the
second (inside `#settle_completed`) moved `generating -> completed`.
Anything that stopped the process between them left the row COMMITTED
`generating` under the operator-paste marker — both action buttons answer
`:already_in_progress` until `RECLAIM_ABANDONED_AFTER`, and the
SERVICE-side reclaim that finally frees the row clears the marker, so the
next trigger buys over the paste after all. Moving the supersede gate
above `enqueue!`/`start_generating!` closed the window on the ordinary
path and left it open on this one.

The arm's own reclaim does not have that last failing: it stands
down on a paste marker rather than claiming over it, so a pipeline run
arriving at such a row settles it onto the pasted body. The service-side
reclaim is still the one that clears the marker, so keeping this window
shut still matters.

An in-process raise made it worse than that: the catch-all at the end of
`#perform` calls `#record_failure`, which found a committed `generating`
row and marked it FAILED — so the operator read "Failed" over their own
pasted summary, and the retry, arriving at a state the paste never
produced, could not finish the hand-off either.

The spec pinning this drives an in-process raise, not a worker kill,
because an in-process raise is the only version of "stopped part-way" a
test can actually drive. It turns out to be the sharper check anyway: on
the old two-lock version, a raise mid-hand-off runs the catch-all, and
`#record_failure` finds the committed `generating` row and marks it
FAILED — a worker kill alone would not exercise that path.

`PasteSummaryService#settle_pasted_row!` runs the same three transitions
in one lock for the same reason. `#settle_completed`'s own
`#settle_under_lock` JOINS this transaction rather than opening a second
one, so the shared tail is kept and there is still one `BEGIN IMMEDIATE`
and one `COMMIT`. A raise anywhere inside rolls the row back to where the
paste left it, where `#record_failure` declines and the retry can pick the
hand-off up again.

`recompute_score: false` here too: this path is by definition a run that
made ZERO adapter calls — the supersede gate at the top of `#perform`
returns before `Llm::Client.build` is reached — so it moved none of the
score's inputs and the recompute would append a row to a table that
exists to record score movement.

### A spec pinning "no recompute" on the supersede path is not a test of the recompute rule

`generate_bill_summary_job_spec.rb` has an example asserting no score
recompute is enqueued when a paste settles the row via the supersede gate.
That example never reaches `#settle_completed` at all — the paste settles
the row itself, so `#settle_superseded_row`'s in-flight check returns
first, before the code that actually decides whether to recompute ever
runs. The example is worth having, because it pins that the whole
stand-down path spends nothing, but it is NOT evidence for the recompute
rule stated above, and it should not be read as standing in for one. A
sibling example against the hand-off path (where `#perform` genuinely
reaches the recompute decision) is what actually exercises that rule.

A nil result from the surrounding `#settle_under_lock` here is the
swallowed `RecordNotFound`: no row left to hand off, and nothing further
to do either way.

## The stale-job gate's own spec pins only one of the five paths

The stale gate (`#stale?`) must not record its stand-down as a completed
stage: this job produced nothing and will not. That branch is unreachable
from the pipeline today — the pipeline's inline `perform_now` call sets
`enqueued_at` to `nil`, which never reads as stale — but a bare `return`
here is the exact regression an earlier finding was filed about, and only one of the
five gates the paste hand-off rule covers was pinned by a spec at the time
the stale-gate gap was found. Each of the other four needs its own spec pinning the
same non-completed contract.

## Why finding the stale-gate gap was deterministic, not a race

`PasteSummaryService` declines to settle a `pending` row and logs that a
queued `GenerateBillSummaryJob` owns its status and will settle it. Before
this fix, the stale gate ran roughly 70 lines before the supersede gate and
moved the row to `skipped` on `enqueued_at` alone, without ever reading
`summary_run_id` — so it claimed the row out from under the paste
regardless of who wrote it last.

Whether that stale job or `ReclaimAbandonedSummaryRunsJob` reaches the row
first is not a coin flip in production: the paste bumps `updated_at`,
which is what the reclaim sweep's own staleness window reads (see
[bill-llm-run-reclaim-timing.md](bill-llm-run-reclaim-timing.md)), so the
freshly-pasted row reads as recently touched and the reclaim sweep cannot
claim it before the worker drains its backlog and the queued job's own
stale check runs. The bug this test pins was therefore certain to fire on
every deferred paste that outlived `STALE_AFTER`, not an occasional race —
which is why it needed a fix, not a wider timing margin.
