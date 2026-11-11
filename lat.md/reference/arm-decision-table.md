---
lat:
  mode: reference
---

# What SummaryRunArmDecision decides

`SummaryRunArmDecision` is the one place that decides what `GenerateBillSummaryJob`'s arm may do with the row in front of it.

- For why this logic is a single class rather than guards inside the arm, and the history of four consecutive reviews that each fixed one branch and missed the next, see [[docs/explanation/bill-summary-arm-row-ownership.md|bill-summary-arm-row-ownership.md]]. This document is the reference: the inputs the decision reads, the invariants it protects, and its nine cases.

## The inputs

Four values, all read from state the caller has reloaded under the row's write lock, plus the status the job loaded before it took that lock:

- **`status_at_load`** - the `generation_status` `#perform` loaded. Nothing
  in the job writes the row between that load and the arm, so a difference
  from the committed status is another writer's work.
- **`status`** - the committed `generation_status`.
- **`marker`** - `summary_run_id`, which has four shapes: absent, an
  operator's paste, `"run:<job_id>"` (one execution's claim on a row it
  armed), and a bare `job_id` (that enqueue's receipt for a body it already
  paid for). See `SummaryRunMarker`.
- **`updated_at`** - the abandonment clock. This is NOT the same clock as
  the stale gate at the top of `#perform`, which reads the job's
  `enqueued_at` and is re-stamped on every retry. Confusing the two is how
  a live owner became reclaimable.

## What the table protects

Each of the following is paid for by an earlier defect:

1. Two executions must never both reach a paid call over one row.
2. A row must never strand with no way out.
3. A live owner inside its paid region must never be reclaimed.
4. An operator's paste must never be overwritten, and the status hand-off it
   defers must never be dropped.
5. A recorded stage outcome must be honest.

- Invariant 3 is why `#refresh_clock?` answers the same as `#proceed?` rather than tracking the marker write: an execution that proceeds IS the live owner, and `updated_at` is the only thing that says so. Every proceeding case restarts it, including the two that leave the marker alone.

## The cases

Tested in this order.

- `proceed?` is false only for the three `DECLINED` cases; `claim_row?` is true only for the three `CLAIMING` cases; `refresh_clock?` always equals `proceed?`; `log_reclaim?` is true only for `reclaim_abandoned`.

| Case | proceed? | claim_row? | log_reclaim? | Meaning |
|---|---|---|---|---|
| `row_moved` | no | no | no | Another writer settled or re-armed the row between the job's load and this lock, so the transition would be validated against a row that is gone. |
| `paste_hand_off` | yes | no | no | A human wrote the body onto a row that is IN FLIGHT. Proceed WITHOUT claiming, so the pre-call clear can settle the row onto the pasted body - the hand-off `PasteSummaryService` defers. Nothing is bought: the clear re-reads the marker and stands the run down before the LLM client is built. |
| `paste_already_settled` | no | no | no | A human wrote the body onto a row that was not in flight, so `PasteSummaryService` settled it itself and deferred nothing. No hand-off is left to complete, and re-arming it would walk a finished row back through `pending` and `generating` for a run that buys nothing. |
| `own_claim` | yes | yes | no | This execution armed the row and came back to it (a restarted worker carries the same `job_id`). |
| `resume_after_purchase` | yes | no | no | This enqueue already paid for a body on this row and is here to finish the half it still owes. The receipt stays, or the re-entry gate would tell the next execution nothing had been bought. |
| `reclaim_abandoned` | yes | yes | yes | `generating` for somebody, and nothing has written the row for longer than the job's worst-case wall clock, so that somebody is gone. |
| `owned_by_another_run` | no | no | no | `generating` for a run that is still alive. |
| `arm_after_purchase` | yes | no | no | Not generating, and carrying this enqueue's receipt: a retry over a row an earlier execution already settled. Arm it so the settle can run, and keep the receipt so it buys nothing. |
| `arm_free_row` | yes | yes | no | Nobody owns it. The ordinary generate, regenerate and pipeline path. |

- The paste test runs ahead of the status and the clock, so a paste-marked row is never reported as a reclaim. But the marker alone cannot say whether there is a hand-off to complete: `PasteSummaryService` declines to settle only a `pending` or `generating` row and hands the status to this decision; on every other status it settled the row itself.

## decide: why the paste test runs ahead of the status and the clock

The paste test runs ahead of the status and the clock, so a paste-marked row is never reported as a reclaim.

- But the marker ALONE cannot say whether there is a hand-off to complete: `PasteSummaryService` declines to settle only a `pending` or `generating` row and hands the status here, and on every other status it settled the row itself. The table used to fold both into `:paste_hand_off` and re-arm a finished row.

## Why PENDING is declared here at all

`PENDING` sits beside `GENERATING` because the two together are exactly the statuses `PasteSummaryService#settle_pasted_row!` defers on.

- Nothing else in this file reads `PENDING`; it exists so the paste rows can be split on the same test the service splits on, rather than on a copy of it.

## Why CLAIMING excludes the two markers the arm may not destroy

`CLAIMING` lists the cases that stamp `"run:<job_id>"` over whatever is there. The two cases it excludes are the two markers the arm may not destroy: an operator's paste and this enqueue's own purchase receipt.

## refresh_clock?: why the timestamp write has to track proceed? exactly

`update_columns` does not bump `updated_at`, and on every proceeding case that finds the row already `generating` no state transition fires either.

- `#abandoned?` is the only thing that decides a run is dead, so an execution that proceeds and does not restart this clock could be reclaimed while its own paid call is still in flight. Tying `#refresh_clock?` to `#proceed?` exactly, rather than tracking the marker write separately, is what keeps that from happening.

## log_reclaim?: why it fires for exactly one case

The log key here is what an on-call reader greps for a dead worker, so it may not fire for a healthy paste hand-off that merely happens to be old — only for the one case that actually reclaims an abandoned row.

## abandoned?: the shared constant, and why a nil timestamp is not abandoned

`#abandoned?` reads `GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER` rather than a second constant of its own: two numbers for one judgement is how the two halves of a rule drift apart.

- `GenerateBillSummaryService`'s own comment carries the argument for the value.

- A nil `updated_at` is NOT abandoned. Every row this application writes has one, so a nil means something built the row outside the ordinary path, and "unknown" must not read as "free" on the decision that opens two paid calls.
