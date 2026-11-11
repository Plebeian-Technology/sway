---
mode: explanation
summary: "Explains LlmSummaryInFlightNotice's wording decisions: which column answers which question (who wrote the summary vs who owns the row), why the draft may predate the run it's shown under, and why Approve's aria-describedby is wired the way it is."
status: agent-extracted
related: [docs/explanation/abandoned-run-reclaim.md, docs/explanation/llm-summary-notice-phrase-pairing.md, docs/explanation/org-position-approval-guard-chain.md, docs/explanation/bill-summary-published-vs-draft-box-bug.md]
---
<!-- vale Vale.Spelling = NO -->

# Why LlmSummaryInFlightNotice reads the way it does

Arming a run clears nothing — the last run's summary/drafts stay on screen
for as long as the queue takes. This notice stops that from reading as the
new run's output.

## `hasDraft`

`llm_summary` — the last run's draft. NOT the editor's text: that's
`bills.summary`, written by no run. Used to promise the new run would
replace "the summary" on screen — it will not. See
[the published-vs-draft box bug](bill-summary-published-vs-draft-box-bug.md).

## `pasted` names who wrote the SUMMARY only

`isOperatorPasted(llm_provider)` — WHO wrote the SUMMARY only:
`llm_summary` and `llm_provider` share two writers, each writing both in
one statement. Says nothing about the positions.

THE SUMMARY HAS A WITNESS: `llm_provider` always names whoever wrote
`llm_summary` (both written in one statement). This notice used to say
"from the last run" over an operator's own paste.

THE POSITIONS HAVE NO WITNESS: a pasted row can carry an earlier run's
positions, and a model-named row can carry the operator's. Say they're
there, claim nothing about who made them.

Used to date these cards a second time, wrong for the same reason as
above. What matters: release doesn't swap the cards — `SummaryRunRelease`
writes only `generation_error` and the status.

## `pasteOwnsSummaryRun` names who OWNS THE ROW

`paste_owns_summary_run` — WHO OWNS THE ROW, derived from
`summary_run_id`, not `llm_provider` like `pasted`. Only this predicts the
sweep; they disagree on a pasted-then-regenerated row. See
[Reclaiming an abandoned summary run](abandoned-run-reclaim.md) ("Which
writer owns a reclaimable row").

THE TEST IS `pasteOwnsSummaryRun`, NOT `pasted`: after a paste then
Regenerate, `llm_provider` still says `operator_paste` with no marker, so
asking the wrong column hides the operator's real exit.

A pasted row is finished for free, not released with a message:
`SummaryRunRelease` diverts to `.hand_off_paste!` when the paste marker is
present, leaving a queued/running row for the sweep to settle.

## `abandoned`

The server's judgement that this queued/running row has nothing writing
to it — same status, opposite message: no new run to wait for, nothing
will replace what's on screen.

The whole promise needs a run to fulfill it. A reclaimable row has none —
the worker died — so waiting means up to 15 minutes for the sweep.
Regenerate is that row's exit.

## When the draft predates the run it's shown under

ON `generating` THE DRAFT MAY PREDATE THIS RUN: `llm_summary` persists
before the positions call, so a killed worker's summary looks like an
earlier run's. On `pending`, nothing has run yet.

Only the live arm names a second run: on `generating` the draft may be
THIS run's own work, so the abandoned arm points back at the run already
on screen rather than asserting a new one.

## The abandoned-run fate wording

`SummaryRunRelease` settles `pending` with `RELEASED_UNSTARTED_ERROR`
(never started) and `generating` with `RELEASED_IN_FLIGHT_ERROR` (stopped
part-way) — only `generating` could have started. See
[llm-summary-notice-phrase-pairing.md](llm-summary-notice-phrase-pairing.md).

## Why Regenerate is not offered as a free fix for a paste

The old "Regenerate to start a new one" advice cost money too: Regenerate
deliberately overrides a human's paste, spending the operator's money to
destroy text the sweep would keep for free.

## Approve's aria-describedby wiring

The id is what a card's greyed-out Approve points its `aria-describedby`
at, so the reason reaches a screen reader that cannot tab to the button.
See [The approval guard chain](org-position-approval-guard-chain.md)
.

The run replaces only what it wrote — draft summary/positions — never
`bills.summary`, so the editor's text stands regardless.

Said as the gate, not a promise: `runInFlight` is `pending || generating`,
so the sweep reopens Approve by moving the row away — no run ever
finished. Used to say "until a run finishes".

Out of the ternary since its pointer isn't: Approve's `aria-describedby`
aims here on BOTH arms. Used to live on the RARE abandoned arm, so the
ordinary arm's screen reader heard nothing.

Used to say "Sway releases the run" on the ordinary live arm too — but
`SummaryRunRelease` is only what the sweep calls on an abandoned row, not
what a run finishing does.
