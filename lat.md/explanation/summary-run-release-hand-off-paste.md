---
lat:
  mode: explanation
---

# Why hand_off_paste! finishes a pasted row instead of refusing it

`SummaryRunRelease.hand_off_paste!` is public, not just a private helper for `.call`.

The promise it keeps was made by the paste, not by the release: `PasteSummaryService` declines to settle a row that is `pending` or `generating`, and names whoever reaches that row next as the owner of its status.

## Why it has to be one method

Four gates inside `GenerateBillSummaryJob` can be that next arrival, and each can move the row to a terminal status without asking: the stale-job gate, `#record_failure`, and the two no-summary settles.

`skipped` and `failed` both sit outside `#reclaimable?`, so a hand-off dropped at any one of those four gates was dropped for good. Keeping the rule in one method means a fifth gate cannot invent a fifth version of it.

## What it does and does not check

The caller decides whether to hand off; this method decides what handing off means.

It is deliberately not gated on `#reclaimable?` — a job standing down inside its own still-running turn is not a reclaim, and has no clock to wait out.

The paste marker is the first test `SummaryRunArmDecision` applies, ahead of the status and the clock, and this method checks it in the same place for the same reason: a row a human wrote by hand is never treated as a reclaim.

## Why finishing beats refusing

Finishing the row, rather than refusing it, is what keeps the promise `PasteSummaryService#settle_pasted_row!` made.

That method declines to settle an in-flight row and logs that a queued or running `GenerateBillSummaryJob` owns its status and will settle it. When that job's worker dies, nothing else is left to keep the promise. `hand_off_paste!` runs the same steps the paste itself would have run, minus `enqueue!` — that step only fires on a row that is not already in flight, and every caller here reaches a `pending` or `generating` row (the state machine's enqueue edges all start from `nil` or a terminal status). The body itself is already committed by the time this method runs.

## Why a stale generation_error is cleared before the hand-off completes

A message from an earlier run must not survive onto a completed row: the panel shows `generation_error` beside a finished summary and would be reporting a failure that did not happen to this body.
