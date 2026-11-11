---
mode: explanation
summary: "Explains why PasteSummaryService writes the audit entry atomically with the pasted body, but rescues the later status settle instead of joining it."
status: agent-extracted
related: []
---
# Why the paste write is atomic but the settle is rescued

<!-- vale Vale.Spelling = NO -->

`PasteSummaryService#call` makes two writes after a pasted summary passes
schema validation: it commits the summary body together with a
`paste_summary_accepted` audit entry, then tries to move the row's status
forward with `#settle_pasted_row!`. The two writes are handled
differently on purpose.

## The body write is atomic with its audit entry

`#write_pasted_body!` puts `PipelineActivityLogEntry.create!` inside the
same transaction (or the same `with_lock` block) as `provisioning.save!`.
This is the only arrangement where the audit log and the stored summary
cannot disagree: either both commit, or neither does, and a failed
attempt can simply be retried.

That matters because of an earlier defect. The audit write used to run after the
transaction had already committed, unguarded, with no rescue anywhere
above it — not in this service, not in `BillsController#paste_summary`.
A `SQLite3::BusyException` on that write escaped to the controller, which
told the operator the paste had failed. It had not: the summary was
already live on the bill and eligible for promotion to the public
`bills.summary`, but the audit log carried no record that a paste had
happened at all. Making the write atomic closes that gap — a body that
commits always has a matching audit entry, and a body that doesn't commit
leaves nothing behind to explain.

`PipelineActivityLogEntry`'s delivery hook fires on the outermost commit,
which is exactly why nesting the audit write here works: the
notification only goes out once the whole paste — body and log entry —
is durable.

## The settle is rescued, not joined, and that is a different decision

`#settle_pasted_row!` runs on the next line, after the write above has
already committed. It is not inside that transaction, and its own
failures are rescued rather than allowed to raise. The fix for that defect once described
the audit write as "the last unguarded post-commit write in this method."
It was not: this settle call was the one it stepped over, and by the time
it runs, the body and its audit entry are already permanent.

Rescuing here rather than joining the two writes into one transaction is
deliberate, for the following reason. `#settle_pasted_row!` opens
`provisioning.with_lock` — a second `BEGIN IMMEDIATE` on the same busy
SQLite database — and then runs up to three state-machine saves. If that
raised uncaught, the retry cost would be worse than the body write's,
and certain rather than possible:

- The audit entry is already committed, so retrying `#call` writes a
  **second** `paste_summary_accepted` for one accepted paste.
- The delivery hook has already fired on the body's own commit, so the
  acceptance notification goes out before the operator ever sees the
  500.
- The row is left `failed`, so the Bill Creator draws its Retry button —
  which buys a fresh, paid generation over the text the operator just
  pasted.

Telling the operator their paste failed, after the body has committed, is
a false statement no later code can take back. Rescuing means the
service can say something true instead: the paste succeeded, but nothing
moved the status.

## What "accepted" means versus what "settled" means

The audit entry recorded by `#write_pasted_body!` means the pasted body
was accepted and is now the row's stored text. It says nothing about
whether the row's `generation_status` reflects that — `#settle_pasted_row!`
can decline to move the status on purpose (see
[paste-summary-status-reuse-and-pending-bug.md](paste-summary-status-reuse-and-pending-bug.md)
for when it hands the row to a job instead), or it can fail to move it,
which is what gets rescued here.

## Deciding whether the operator needs to be warned

After the rescue, `#call` still has to decide what to tell the operator.
`#settlement_still_expected?` answers that by re-reading the row's status
under a fresh load (the raise can come from inside `with_lock`, before its
own reload runs, so the in-memory copy may be stale):

- `pending` or `generating` — a `GenerateBillSummaryJob` owns the status
  and will settle it on its own. Not a failure.
- `completed` — the row is already where the settle was trying to take
  it.
- Anything else (`nil`, `failed`, `skipped`) — no job is attached and none
  will be created. The status stays wrong until an operator acts, so
  `#call` returns `:persisted_unsettled` instead of `:persisted`.

`failed` is the worst of those three, because a failure is exactly why an
operator pastes a replacement in the first place. Leaving it unmoved and
unexplained means the operator sees the paste reported as saved, and then
reads a red "Failed" banner over the summary they just wrote, with no
control that clears it short of pasting again — and nothing tells them to
do that.

If the re-read itself fails, `#settlement_still_expected?` answers "no" —
the safer side to be wrong on (the full reasoning is in the comment on
that method itself, kept in code since it is a tight, single-idea note
rather than documentation).

## Why the settle-failure spec stubs `#settle_pasted_row!` by name

`spec/requests/bills_paste_summary_spec.rb`'s "tells the operator when the
paste saved but the status did not move" example stubs
`PasteSummaryService#settle_pasted_row!` directly to raise
`ActiveRecord::LockWaitTimeout`, rather than stubbing
`BillLlmProvisioning#with_lock` — the lock `#settle_pasted_row!` happens to
take. Since the pasted body is now written under a lock of its own,
`with_lock` is also the lock the write itself takes. Stubbing the shared
mechanism failed whichever step reached it first, so the example stopped
being about the settle step at all. Naming the method directly targets
only the step under test.

## `#settlement_still_expected?`: full reasoning (superseding the note above)

This is asked only after the settle raised, so it decides whether
anything is still going to move this row's status.

`pending` and `generating` mean a `GenerateBillSummaryJob` owns the
status — that is the hand-off `#settle_pasted_row!` makes on purpose, and
it is not a failure. `completed` means the row is already where the
settle was taking it. Every other value (`nil`, `failed`, `skipped`) has
no job attached and none coming, so the status stays wrong until an
operator acts.

The row is re-read rather than trusting the in-memory copy: the raise can
come from `with_lock` itself, before the reload inside it, so the object
may hold the status this service loaded rather than the committed one.

A failure of the re-read answers "no". Between over-warning and telling
an operator their work is saved when the row still says Failed,
over-warning is the honest side to be wrong on.
