---
mode: explanation
summary: "Why ReclaimAbandonedPipelineRunsJob and ReclaimAbandonedSummaryRunsJob rescue per row, oldest-first, instead of letting one bad row end the sweep."
status: agent-extracted
related: [abandoned-run-reclaim]
---

<!-- vale Vale.Spelling = NO -->

# Why the reclaim sweeps rescue per row instead of per sweep

`ReclaimAbandonedPipelineRunsJob` and `ReclaimAbandonedSummaryRunsJob` both
process their candidates oldest first (`.order(:updated_at)`), and both
rescue inside the per-row loop rather than around the whole sweep.

Oldest-first with a sweep-level rescue would mean a row that raises leads
every tick and hides every row behind it — absorbing the exception per row
is what stops that. In `ReclaimAbandonedSummaryRunsJob`, `#reclaim` rescues
`RecordNotFound` alone, and everything else it can raise is routine on a
single Pi: a `SQLite3::BusyException` wrapped as `StatementInvalid` under a
competing writer, a `RecordInvalid` from the state-machine save. Escaping
the block would end the sweep, and since it is oldest-first, the row that
raised would lead every later tick and the rows behind it would never be
reached. `ApplicationJob` declares no `retry_on`, so nothing would come
back for them.

The failure log for each skipped row is worded so a repeat is
recognizable: the same row appearing every tick is a row that needs a
person, not a transient blip the sweep will clear on its own.

## Why `RecordNotFound` is rescued around the lock, not the loop

Both `#close` (pipeline runs) and `#reclaim` (summary runs) wrap
`with_lock` in its own `rescue ActiveRecord::RecordNotFound` returning
`false`, for the same reason: the row was destroyed between the query and
the lock — most likely by the orphan delete — and that is not a failure
worth logging as one, just nothing left to free.

## Why the row count per sweep is bounded

Each sweep bounds `MAX_ROWS_PER_SWEEP` so one sweep cannot hold the writer
lock over an unbounded set on a single Raspberry Pi. Anything past the
bound is picked up by the next run.
