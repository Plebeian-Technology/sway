---
mode: explanation
summary: "Explains why a legislation pipeline run can end as partial rather than succeeded or silently stuck, and how failed bills are counted from stage_results."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why a legislation pipeline run can end partial, not just succeeded

## Guaranteeing a terminal state

`RunLegislationPipelineJob`'s DAG loop finishing without a raise means the
run ended well — but "well" splits two ways. If any bill failed at least
one stage while the run as a whole still produced output, the run is
`:partial`, not `:succeeded`. `mark_succeeded!` used to fire
unconditionally, so an operator saw a green run with no hint that some
bills produced no summary; the `mark_partial` event existed in the
`LegislationPipelineRun` state machine but was never called.

And if the loop exits cleanly but the run is not in `:running`, the job
must not silently bail. An earlier `return unless can_mark_succeeded?` left
such runs orphaned in a per-stage status (`fetching_hearings`, etc.)
forever — no `error_message`, no audit log, only a stale "in flight"
banner. This happened when a dev machine slept mid-stage and a stage's
`complete_X!` transition never ran.

`#finalize_run_terminal_state` guarantees a terminal state on every exit
path: every other path goes through `#handle_run_failure` (which
force-fails non-terminal mid-stage states); this was the only path that
did not.

## Reading failure from stage_results, not the coarse status column

`#count_failed_bills` reads per-bill failure from the `stage_results` JSON,
not the coarse `pipeline_run_bills.status` column. A bill that succeeds an
early stage then fails a later one (a summarize-stage LLM failure, say)
keeps `status="succeeded"`, because the `mark_failed` event cannot fire
from `:succeeded`. `stage_results` records every per-stage outcome; a bill
counts as failed when any bill-level stage recorded a `"failed"` result.
The stage names in the SQL come from the frozen `BILL_LEVEL_STAGES`
constant, so nothing user-supplied reaches the query — the same pattern as
the `json_extract` accounting in `#run_bill_level_stage` (see
[Pipeline bill stage status model](pipeline-bill-stage-status-model.md)).
