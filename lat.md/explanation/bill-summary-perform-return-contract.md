---
lat:
  mode: explanation
---

# Why GenerateBillSummaryJob.perform reports what it did

For the two return values themselves, see [[docs/reference/bill-summary-job-return-values.md|../reference/bill-summary-job-return-values.md]]. This document explains why they exist.

## The caller could not tell from the outside, and used to guess wrong

`RunLegislationPipelineJob` calls `GenerateBillSummaryJob#perform_now` inline, and used to record the pipeline's `summarize` stage as "succeeded" whenever `#perform` returned normally.

Several code paths return normally having produced nothing and having settled nothing:

- The declining rows of `SummaryRunArmDecision` (see
  [[docs/explanation/bill-summary-arm-row-ownership.md|bill-summary-arm-row-ownership.md]]).
- The two "the row is gone" returns, one inside
  `#arm_row_unless_owned!` and one inside
  `#clear_stale_run_state_unless_superseded!` (the pre-call clear).

The most reachable of these is not exotic: an operator's queued job can be inside its paid region — up to six minutes — when a pipeline run reaches the same bill.

When that happens with no return-value contract, the bill ends with no summary, its pipeline stage recorded as succeeded, and `resume` skips it forever. `RunLegislationPipelineJob` names this exact harm in its own comments, a few lines above its call site, as a bug it already paid for and fixed once.

## The fix

`#perform` now always returns one of two symbols (defined in [[docs/reference/bill-summary-job-return-values.md|../reference/bill-summary-job-return-values.md]]):

- `NOT_RUN` — the caller must not record the stage as done.
- `SETTLED` — this execution settled the row, whatever it settled it to.

`RunLegislationPipelineJob` reads this return value instead of assuming success from a normal return, so a "produced nothing, settled nothing" execution is recorded as not-run and gets picked up again by `resume`.
