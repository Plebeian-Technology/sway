---
mode: explanation
summary: "Explains why the transition that releases an abandoned bill-summary run lives in one shared class instead of being copied into each caller."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the abandoned-run release has one home

`SummaryRunRelease` is the one place that moves a bill-summary run whose
writer is gone into a terminal status: `generating` to `failed`, or `pending`
to `skipped`.

## Where the transition used to live

The transition first lived inside
`GenerateBillSummaryService#reclaim_abandoned_run!`. Three things about that
one caller made it safe there:

- it re-arms the row microseconds later and clears `generation_error` on the
  way, so any message written there is only ever read by the code that
  erases it
- it only runs after an operator clicks Generate or Regenerate — the one
  route that is allowed to override a summary a human pasted
- it holds exactly one row, so it has nothing else to keep going for

## What went wrong when a second caller reused it

`ReclaimAbandonedSummaryRunsJob` later reused the same transition, and had
none of those three properties. Each missing property turned into its own
defect:

- An operator read "An unknown error occurred" on a row where
  nothing had actually failed.
- A paste hand-off that had been deferred landed on `failed`
  with no way back.
- One row raising an error stopped the sweep for every row
  behind it.

## The rule the single home enforces

The transition therefore has one home, and that home makes the caller answer one
question before it can run: does anything else take this row on afterward?
Neither caller can reach the transition without answering that question —
it is the `rearmed_by_caller:` argument to `SummaryRunRelease.call`. The
third property, whether the caller is sweeping many rows or holding just
one, is the caller's own business and stays with the sweep, not with this
class.
