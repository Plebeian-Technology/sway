---
mode: explanation
summary: "Explains why sync_pipeline_run_stage closes a stage row as failed, not cancelled, when a run is cancelled mid-stage."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why a cancelled stage row is marked failed, not cancelled

`LegislationPipelineRun#mark_cancelled!` can fire from every per-stage
`*ing_*` state, not only from `queued`/`running`. Before the branch in
`sync_pipeline_run_stage` that handles this existed, only the
`*ing_* -> failed` path closed the matching `pipeline_run_stages` row. A
mid-stage cancel left that row stuck in `:running` with `finished_at` nil,
and the per-bill grid header showed "stage still in flight" on a run that
was already cancelled.

## Why it reuses the failure path instead of a cancelled state

`PipelineRunStage` does declare a `:mark_cancelled` event, but nothing in
the app calls it, and the frontend's stage status union carries no
`"cancelled"` member — a stage moved there would render with no status at
all. `sync_pipeline_run_stage` mirrors the failure handling instead
(`mark_failed!` plus stamping `finished_at`), because both `failed` and
`cancelled` mean the same thing to a reader of the stage row: "this stage
did not succeed, do not show a green check."

The unused `:mark_cancelled` event on `PipelineRunStage` is still to be
removed.

## Why a stage that already succeeded must not be touched by a later cancel

A stage that already finished successfully earlier in the run must not be
touched when a later stage gets cancelled. Only checking the case where
the run cancels the stage that was actually running would miss this
cross-stage case — without it, a future change to
`sync_pipeline_run_stage` could accidentally reach back and flip the
already-succeeded row to failed too (WR-NEW-03).

## Why cancelling from the plain :running state must not create or touch any stage row

Cancelling from the plain `:running` state — no stage in flight, because
the operator clicked cancel between stages — must not create or touch any
`pipeline_run_stages` row. That state has no entry in
`STAGE_STATUS_TO_DAG_NAME`, so the "mark the stage failed" logic above
must not fire for it. This guards against a future change that catches the
`running -> cancelled` move and wrongly marks the last succeeded stage as
failed (WR-NEW-03).

The spec's `let(:run)` already invokes `start_running!` during creation
(`queued -> running`); the example asserts that state precondition
explicitly (`expect(run.status).to eq("running")`) so a future change to
the `let` setup is caught rather than silently testing a different
transition.
