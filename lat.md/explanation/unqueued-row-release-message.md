---
lat:
  mode: explanation
---

# The unqueued-row release message

`GenerateBillSummaryService::UNQUEUED_ERROR` is what an operator reads on a row `#release_unqueued_row!` put back after an enqueue failure.

## Two writers reach skipped, and mean different things

Two different writers can leave a row `skipped`, and a row that carries no reason gets the other writer's.

The Bill Creator panel prints whatever reason a `skipped` row holds, and falls back to the stale gate's sentence — "It waited in the queue too long, so the worker passed it over" — when there is none. That sentence describes a job that WAS queued. `#release_unqueued_row!` runs when the job could NOT be queued, so `UNQUEUED_ERROR` has to say so itself, the same way `SummaryRunRelease` writes its own sentence for each of its two arms (see [[docs/reference/summary-run-release-message-invariants.md|../reference/summary-run-release-message-invariants.md]]).

`UNQUEUED_ERROR` names the cost because that is the operator's next question, and the answer is free: this release runs before anything reaches an adapter.

## The four shapes that reach this message

`UNQUEUED_ERROR` used to say the bill was left as it was.

The same click that fails to enqueue writes before it enqueues, inside the same lock, and `#release_unqueued_row!` undoes none of that write — only the status and the paste marker. Four shapes reach this message, and the "left as it was" clause was false in three of them:

1. No testimony and no clear — only `summary_run_id` and
   `generation_error` moved, and even then the status went to `skipped`,
   so a regenerate of a `completed` row still reads "Skipped" afterward.
2. A first or appending paste — `supplemental_testimony` is stored.
3. A REPLACING paste over existing drafts — `SupplementalTestimonyWrite`
   also stamps `evidence_retracted_at` on every draft, which is what
   `ApproveOrgPositionService` refuses on. The operator was told nothing
   happened and then found every Approve dead.
4. An explicit clear — the column is emptied and the stamps are lifted.

The sentence names what IS true of all four instead: the run cost nothing, and what the operator sent was kept. Why each Approve is refused is stated per card by `BillCreatorOrgPositionCard`'s retraction notice, which is the screen that knows.
