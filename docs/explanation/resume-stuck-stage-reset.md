---
mode: explanation
summary: "Explains why normalize_for_resume resets a stuck per-stage run status and its pipeline_run_stages row, even though the path is currently unreachable."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why normalize_for_resume resets a stuck stage

## The problem it fixes

If a worker was SIGKILLed mid-stage, the run's `status` column stays stuck
in a per-stage `*ing_*` state (for example, `"fetching_law"`). The DAG loop
calls `start_X!`, which only transitions from `:running` — so without a
reset, the run could never move again.
`RunLegislationPipelineJob#normalize_for_resume` soft-resets the column to
`:running` via `update_columns` so the loop can re-enter the affected stage.
Already-succeeded stages are still skipped by `stages_to_run`.

## Currently unreachable, kept as a guard

Both callers that dispatch an `origin: "resume"` job
(`LegislationPipelineRunService#resume`,
`BillsController#resume_pipeline_run`) create a brand-new run row with
`status: "queued"` — never a stuck `*ing_*` row — so
`stuck_states.include?(current_status)` is always false in production. The
reset is kept as a guard in case a future change makes a resume job target
an existing run instead of a fresh one.

Because it is unreachable, nothing would notice if it were wrong. The status
write it performs is the model's `#reopen_stuck_stage!` rather than a bare
`update_columns` call, because that method records the change in the
Activity Log and sends the cable message, which a direct column write
skips. A guard that fires for the first time years from now should not also
be the first write in this system to move a run silently.

## The pipeline_run_stages row is reset too

The stuck stage's `pipeline_run_stages` row is reset as well, if one
exists. The `stages_to_run` filter only skips rows whose status is
`"succeeded"`; a stuck row in `"running"`/`"pending"`/`"failed"` is
correctly retried, but if a stage-row uniqueness constraint or
state-machine transition collides with that stale row on re-entry, the
resume gets stuck again. Any non-terminal stage row is therefore reset to
`"pending"` with its `started_at`/`finished_at` timestamps cleared, and the
next `start_X!` finds the row fresh.
