---
mode: explanation
summary: "Explains the gate that stops the summary job from overwriting an operator's hand-pasted summary, and why it must run early."
status: agent-extracted
related: []
---

# The supersede gate in GenerateBillSummaryJob#perform

<!-- vale Vale.Spelling = NO -->

An operator can paste a hand-written summary onto a bill's provisioning row
after that row was armed (set up for a generate run). When that happens,
the body on the row is human work, and `GenerateBillSummaryJob` has
nothing to add. Near the top of `#perform`, right after the row is loaded
or created, a gate checks for exactly this and stops the job before it
spends anything.

This gate sits next to the re-entry gate (see
[bill-summary-re-entry-guard.md](bill-summary-re-entry-guard.md)) because
the two share one shape — "another writer already owns this row's body, so
make no paid calls and settle the row" — and differ only in who that other
writer was.

## Why a marker, not a status, records the paste

`PasteSummaryService` declines to settle a `pending` or `generating` row.
That stopped a false green "Ready" badge, but it does nothing about this
case: `#perform` creates the provisioning row if it is missing and
re-arms it from ANY status, deliberately, because
`RunLegislationPipelineJob` calls it inline via `perform_now`, and no
status a paste can leave the row in stops this job from walking straight
out of it. "A human superseded me" therefore cannot be expressed as a
status — it has to be a value the job reads. That value is the
`summary_run_id` column, used here as a marker (see `SummaryRunMarker`).

## What an operator sees

Their paste survives. The row they left in flight settles to `completed`
here — the hand-off `PasteSummaryService`'s deferred branch promises.
The Bill Creator renders their body with `llm_provider` `"operator_paste"`.
The stand-down is logged. Nothing is lost silently — that is the one
outcome this gate may not produce.

## When the paste is legitimately superseded

`GenerateBillSummaryService` clears `summary_run_id` inside the lock that
arms the row, so an operator clicking Generate or Regenerate wipes the
marker and the next job makes its paid calls — which is exactly what they
asked for. That service logs the supersede, and on the regenerate path
also writes a `summary_regenerate` audit entry, so the destruction of
hand-written work has a durable record.

## The price this gate accepts

`RunLegislationPipelineJob`'s inline `perform_now` does NOT go through
`GenerateBillSummaryService`, so a full pipeline re-run will not
re-summarize a bill an operator pasted onto. That is the intended
direction — a background sweep may not silently destroy hand-written work
— and the operator's override is the Regenerate button. The leftover is
the same one the nothing-to-generate settlement accepts (see
[bill-summary-nothing-to-generate-settlement.md](bill-summary-nothing-to-generate-settlement.md)):
the stage ran, correctly determined there was nothing to buy, and the row
is the honest signal.

## Why this gate runs before `enqueue!`/`start_generating!`, not after

This gate used to sit after those state transitions, so a row
`PasteSummaryService` had already settled was walked
`completed -> pending -> generating -> completed` on the way to deciding
not to touch it. Nothing about that was free:

- The Bill Creator polls every 5 seconds, so the admin watched a finished
  hand-written summary flicker Queued -> Generating -> Ready for a run
  that bought nothing.
- `#settle_completed` enqueued a score recompute (a write to the queue
  database) for a run in which nothing changed.
- A crash anywhere in that window left the row `generating`, where BOTH
  action buttons answer `:already_in_progress` until
  `GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER` — and the reclaim
  that finally frees the row CLEARS the marker, so the next trigger
  overwrites the paste after all.

The supersede protection was defeated by the very window opened to check
it. `RunLegislationPipelineJob` calls `#perform_now` inline for every bill
in a run, so that race was the ordinary case, not an edge one.

## Why `#superseded_by_operator_paste?` delegates rather than reads the column

`#superseded_by_operator_paste?` calls `SummaryRunMarker.operator_paste?`
rather than comparing `summary_run_id` inline, so the reader and the
writer of this value cannot drift apart — the same one-shared-helper
reasoning `SummaryCitationValidator` applies to the citation columns,
here applied to the other column this file has two writers for.

## The second tier: persist_unless_superseded!

The gate at the top of `#perform` reads the paste marker ONCE, immediately
after the row is armed, so it can only see a paste that already existed.
The window it cannot see is the whole paid region — two adapter calls at
120s apiece with 2 SDK retries each — which is precisely when an operator
who has given up waiting pastes. For a row already `generating`,
`PasteSummaryService` declines to settle and hands the status to this job;
without a second check the job would overwrite the pasted body AND the
marker in one `update!`, while that service's log told the operator the
marker had stopped exactly that.

`#persist_unless_superseded!` is that second check — the compare-and-swap
that decides whether a purchase may LAND, as opposed to the gate above,
which is the cheap pre-check that spends nothing. `#settle_under_lock`
reloads the row under `BEGIN IMMEDIATE` (`config/database.yml`), so no
other connection can commit between the re-read and the write — a genuine
compare-and-swap, not a suggestion. Same two-tier shape as
`ApproveOrgPositionService`'s three guards.

STANDING DOWN AFTER PAYING is deliberate, and it is not a budget decision:
the money is spent either way by the time this check runs. The only
question left is whether a background run may overwrite work a human did
in the meantime, and that is already settled — it may not, and
Regenerate is the operator's override, which clears the marker and pays
again. The discard is logged and the row is settled onto the pasted body,
so nothing is lost silently.

A row DELETED mid-flight yields nil from `#settle_under_lock` (which logs
and swallows `RecordNotFound`) and is reported as `:persisted`: there is
no paste to protect and no row to settle, so claiming a supersede would
name something that never happened. Only `:superseded` can reach the
summary persist's caller — that call passes no `evidence_digest`, so
`:evidence_withdrawn` cannot happen there — and `:superseded` means the
row was already settled onto the operator's paste.

`evidence_digest` adds a SECOND compare-and-swap, for the positions
persist only (the summary persist passes none, since a summary is not
drawn from testimony and so has no evidence to withdraw) — see
[bill-summary-positions-evidence-digest.md](bill-summary-positions-evidence-digest.md)
for what it guards.

## The Bill Creator's paste fallback on a skipped row

PasteSummaryService always writes the body/paste marker; only the STATUS settle defers
on pending/generating (why the supersede gate and hand_off_paste! exist).

On a skipped row nothing is writing and no job is coming, yet Retry alone cost two model
calls before this fallback existed.

`LlmSummaryGenerateBranch` offers it more broadly: pasting is the free
alternative to Retry. Used to show for `failed` only, on the wrong premise
a pending/generating row can not be pasted onto — it can, it just defers
settling status.
