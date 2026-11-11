---
mode: explanation
summary: "Explains GenerateBillSummaryService#call's locking order, why summary_run_id and generation_error are cleared before enqueue, and how a failed enqueue releases the row it armed."
status: agent-extracted
related: [generate-bill-summary-service-overview, bill-summary-supersede-gate, bill-llm-run-reclaim-timing, pipeline-activity-log-summary-regenerate-event]
---

# `GenerateBillSummaryService#call`: locking order and enqueue-failure recovery

See [generate-bill-summary-service-overview.md](generate-bill-summary-service-overview.md)
for what this service owns overall. This document covers the concurrency
mechanics inside `#call` and `#release_unqueued_row!`.

## `initialize`: why only a `String` is accepted as testimony

`params[:supplemental_testimony]` arrives here unpermitted, so a client
sending `supplemental_testimony[]=x` or `supplemental_testimony[a]=b` shows
up as an `Array` or `ActionController::Parameters`. Those are not `nil`, so
they used to take the write branch and get `to_s`-cast into the text
column — storing `["x"]` or `#<ActionController::Parameters ...>` as
testimony that then fed the positions prompt. Anything that is not a
`String` is not testimony.

## Why the provisioning row is created after the `runnable?` guard

`GenerateBillSummaryJob#perform` creates this row on demand too, but
`#call` needs it here to clear stale run state and flip to `pending` before
the enqueue. Mirroring the job's create-on-demand lets a non-amending bill
with no prior provisioning row still be generated (the empty-state path).

This creation is deliberately AFTER the `runnable?` guard: the Bill
Creator's empty state renders based on the provisioning row being absent,
so a call that goes nowhere must not leave a phantom row behind and
silently change which branch the UI shows.

## Why `first_generation` is captured before the lock touches the row

The Bill Creator's empty state posts `/regenerate_summary` too (the only
endpoint that writes an audit entry), so this service is the last place
that can still see whether there was a summary to regenerate. Nothing
below clears `llm_summary`, but capturing the answer here ties the audit
entry to the state the operator actually acted on.

## Why the pending?/generating? guard needs a lock at all

The pending?/generating? guard plus the flip to `pending` used to run
without a lock: check, then act. The state machine validates against stale
in-memory state, so two concurrent Generate clicks could both read
`:completed`, both pass the guard, and both enqueue a job — a duplicate
paid LLM run. `with_lock` opens a `BEGIN IMMEDIATE` transaction
(`config/database.yml` `default_transaction_mode: IMMEDIATE` — only one
writer at a time) and reloads the row, so the second caller sees the
first's committed `:pending` and bails out with `:already_in_progress`
inside the lock.

`marker_before_arm` is declared OUTSIDE the lock's block because the
block cannot hand it back: the block returns the outcome symbol, and a
local created inside it dies with it.

Inside the lock, `#reclaim_abandoned_run!` runs on freshly reloaded state,
BEFORE the pending?/generating? guard reads it — a row abandoned by a dead
worker must be reclaimed here or it never will be. See
[bill-llm-run-reclaim-timing.md](bill-llm-run-reclaim-timing.md).

## Why `summary_run_id` and `generation_error` are cleared before `enqueue!`

Clearing the stale `summary_run_id` and `generation_error` BEFORE
`enqueue!` stops a late webhook from a prior failed run from being able to
`find_by(summary_run_id:)` and overwrite the new pending row. The generate
path also persists the operator's `supplemental_testimony` here — and
regenerate must persist a supplied paste too: when a summary is stale, the
stale header's "Regenerate from latest data" is the only regenerate button
the operator can reach, and it is the one the testimony-attachment warning
points them at. Dropping the paste would leave `testimony_present?` false,
skip the positions call, and still report success.

Clearing `summary_run_id` is also the supersede step: the
column holds an operator-paste marker when a human wrote the summary by
hand (`SummaryRunMarker`), and `GenerateBillSummaryJob` stands down when it
sees one — see [bill-summary-supersede-gate.md](bill-summary-supersede-gate.md).
Clearing it here is what makes a deliberate Generate/Regenerate the one
route that overrides a paste. Destroying hand-written work must not be
silent, so `#log_operator_paste_superseded` announces it first, immediately
before the `update!` that erases the marker it reports on.

`marker_before_arm` is read under the lock, on the state the lock reloaded,
so `#release_unqueued_row!` can put it back if the enqueue fails. The clear
is the supersede ITSELF, not a side effect of the arm, so undoing the arm
has to undo it too.

### The Steep typing trap on the `attrs` hash literal

A trailing `#: Hash[Symbol, String?]` assertion on the `attrs` hash literal
did NOT work — Steep still inferred `Hash[Symbol, nil]` from the literal
and rejected the later assignment with "Cannot pass a value of type
`(::String | nil)` as an argument of type `nil`". The `@type var` form
declares the LOCAL variable's type rather than asserting the expression's,
which is what is needed here. `Llm::StructuredOutputSchema.for_request`
writes up the same trap.

## Why the enqueue and the audit log run after the lock commits

The enqueue and the audit entry run AFTER the lock commits: the job must
not start before it can see the `:pending` row, and the audit entry comes
LAST — it is only written when everything guarded above succeeded.

The enqueue is a write to the QUEUE database, and `SQLITE_BUSY` is the
realistic failure this codebase keeps naming. When it raised, the lock had
already committed, so the row was left `pending` with no job attached and
none coming — and `#reclaim_abandoned_run!`, the only thing that frees such
a row, runs in exactly one place: inside this method, reached only from
`/generate_summary` and `/regenerate_summary`, whose controls are all
disabled while the row is `pending`. The row could not be reached by the
one thing that could fix it, and the only remaining exit was a full
pipeline run over the locale, re-paying for every other bill in it.

The arm is undone in `#release_unqueued_row!` rather than left for a
recovery that cannot be reached.

## Why the audit log is unconditional, not only for regenerate

The `PipelineActivityLogger.log_summary_regenerate_triggered!` call is
logged on BOTH paths. This used to sit inside `if @regenerate`, so the
Generate button — the control an operator reaches on a failed row, or on
one never generated — spent two paid model calls with nothing durable
written down, while the Regenerate buttons beside it were recorded.
Nothing said the split was deliberate, and the payload already carries
`first_generation` precisely so one event can tell the two apart.

## `#release_unqueued_row!`: putting the row back where the arm found it

Put the row back where the arm found it, because the job that was meant to
move it does not exist.

`skipped` rather than the status before the arm: it is terminal and
re-armable (the state machine has `skipped -> pending`), which is the same
edge `#reclaim_abandoned_run!` uses for a stranded `pending` row, and it
leaves the Bill Creator's Generate button enabled so the operator can try
again.

### The paste marker goes back with the status

This paragraph used to say nothing that mattered was lost, because
"`#call` cleared only `summary_run_id` and `generation_error`". Clearing
`summary_run_id` is not incidental to the arm — it IS the supersede.
`SummaryRunMarker` exists to say that column is the one thing standing
between hand-written work and a background run: a regenerate overrides a
paste, a pipeline run that happens to pass by does not. Undoing the arm
without undoing the override left the row overridable by a run the
operator never asked for, after being told their click did nothing
.

The marker is restored only when it was a PASTE, and only onto a row whose
marker is still `nil`. A run claim or a receipt is not the operator's
work, and another writer may have marked the row since. Restoring the same
value cannot collide with the unique partial index, because nothing else
ever held it.

The restore is guarded on `pending?` under the lock for the reason every
re-check in this subsystem is: an inline `perform_now` (the pipeline) may
have picked the row up between the enqueue failing and this line, and a run
that is under way must not be knocked back to a terminal status.

A failure of the release itself is logged and swallowed. By this point the
operator is already getting a plain refusal, and raising would replace it
with a 500 about a row that is no worse off than it was.

### Why the reason goes on the row, not only in the log

The arm cleared `generation_error` on its way in, so without writing
`UNQUEUED_ERROR` onto the row here, the row reaches the Bill Creator as a
`skipped` row carrying nothing — and the panel's fallback sentence is the
STALE GATE's, about a job that waited in a queue. This one never got into a
queue.

## `#log_operator_paste_superseded`: why it logs before the erasing write

The operator is about to replace a summary a human wrote by hand. They
asked for it — this is the intended override, and the only one — but it
is still the loss of work no automated run can reproduce, so it gets a
durable log record. The audit log already records the
regenerate click; this states what that click is displacing, and covers
the generate path too.

It runs INSIDE the caller's `with_lock`, on state the lock has just
reloaded, immediately before the `update!` that erases the marker it
reports on.

## `#reclaim_abandoned_run!`: why it reads `BillLlmProvisioning#reclaimable?`

It reads `BillLlmProvisioning#reclaimable?` rather than the two guards this
used to spell out. The same judgement is now read by the Bill Creator's
prop and by `ReclaimAbandonedSummaryRunsJob`, and three copies of one rule
is how the two halves of a rule drift apart.
