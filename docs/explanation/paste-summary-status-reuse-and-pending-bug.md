---
mode: explanation
summary: "Explains why PasteSummaryService reuses the completed status for a pasted summary instead of a new status, and the pending-row bug that cost a paid regeneration."
status: agent-extracted
related: []
---
# Why settle_pasted_row! reuses `completed`, and the pending bug it fixed

<!-- vale Vale.Spelling = NO -->

`PasteSummaryService#settle_pasted_row!` moves a provisioning row's
`generation_status` to `completed` after a pasted summary body has been
saved. This service writes the text, so it also has to write the status
that decides whether anyone ever sees that text — the Bill Creator only
shows `llm_summary` when the status is `completed` (or `skipped` with an
earlier summary already present).

## Why there is no `pasted` status

The status machine already has every step this needs, and the UI already
knows how to draw the `completed` branch. Reusing it instead of adding a
new status means no model change, no update to the frontend's list of
allowed statuses, and no new decision at every branch that already
exists — all just to say something two other columns already say:
`llm_provider` is set to `"operator_paste"` when the body is written, and
the audit log records `paste_summary_accepted`.

The three steps — `enqueue!`, `start_generating!`, `mark_completed!` —
all run inside one locked transaction, so no other reader ever observes
the in-between `pending` or `generating` values. They exist at all only
because this method walks the real state machine instead of inventing a
shortcut around it.

## The bug: `pending` used to count as "not yet running"

Earlier, the check to decide whether a generation was still in progress
was `provisioning.generating? || provisioning.completed?`. That let a row
`GenerateBillSummaryService` had just set up — a job queued, nothing
started yet — get walked forward: `pending` → `generating` →
`completed`.

The Bill Creator then showed a green "Ready" over the pasted text. When
the queued job finally ran, it went `completed` → `pending` →
`generating`, paid for a fresh summary, and overwrote `llm_summary`,
`llm_full_breakdown`, `llm_generated_at`, and the citation verdict — all
with the operator's pasted work underneath them. Nothing anywhere
recorded that this had happened.

Every other place in the app treats "queued" and "running" as the same
state — `GenerateBillSummaryService`, the frontend's
`LlmSummaryStatusShell`, and `BillCreatorSummaryAndPositions`. This
method was the one place that split them, and the fix is to stop
splitting them: `pending` now counts as still running, and this method
leaves the status alone when the row is `pending` or `generating`,
handing the row to whoever owns that run.

## Leaving the status alone is only half the fix

Not settling the row stops the false "Ready," but on its own it does
nothing to stop the queued job from overwriting the pasted text later —
`GenerateBillSummaryJob` is built to restart from any status it finds.
The other half is the operator-paste flag `PasteSummaryService#call`
writes onto `summary_run_id` in the same write as the body. When
`GenerateBillSummaryJob` sees that flag, it stands down: no paid call, no
overwrite. The status change is left for that job to finish once it runs
— this branch hands off to a known owner instead
of giving up on the row.

Either way — whether this method advances the status or leaves it for the
job — the pasted text itself is already saved unconditionally, before
this method ever runs. Declining to settle only delays when the status
catches up with it.

## Why this method writes a status at all

Before this method existed, pasting onto a row whose status was `nil`,
`pending`, `failed`, or `skipped` saved `llm_summary` and left the status
untouched. The Bill Creator only shows `llm_summary` when the status is
`completed` (or `skipped` with an earlier summary already present), so
the pasted text was invisible and could not be promoted to
`bills.summary`. `failed` was the worst case: a failure is exactly why an
operator pastes a replacement, and that branch of the UI offered only a
Retry button — the one moment a manual paste needed to work, it didn't.

## Why `#settle_pasted_row!` re-reads the status under the lock

The status is re-read under the lock rather than trusted from the copy
loaded before `#write_pasted_body!` ran: `generating` may have started, or
another writer may have settled the row, in the time since `save!`
committed the pasted body.
