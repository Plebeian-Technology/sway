---
lat:
  mode: reference
---

# RunLegislationPipelineJob behavior

`RunLegislationPipelineJob` is the one background job that runs the whole legislation pipeline — fetching bills, extracting text, summarizing, and so on — on Solid Queue.

## How it behaves

Concurrency controls, conflict handling policies, and runtime invariants enforced by the pipeline job.

- `limits_concurrency to: 1, on_conflict: :raise` — at most one
  `RunLegislationPipelineJob` is ever active, anywhere. A second enqueue
  raises so the caller (`BillsController`, a manual trigger, etc.) can return
  HTTP 409 ("already running"). See
  [[docs/reference/legislation-pipeline-concurrency-layers.md|Legislation pipeline concurrency layers]]
  for the full locking design.
- `RUN_LEVEL_STAGES` (`fetch_bills`, `fetch_law`) run exactly once per run.
- `BILL_LEVEL_STAGES` loop over `run.pipeline_run_bills`. Each bill's outcome
  is written to the `pipeline_run_bills.stage_results` JSON column. See
  [[docs/explanation/pipeline-bill-stage-status-model.md|Pipeline bill stage status model]]
  for what the possible outcomes mean.
- A bill-level stage aborts after 5 bills fail in a row
  (`CONSECUTIVE_FAILURE_BUDGET`).
- Resume mode (`origin: "resume"`) skips stages that already succeeded on the
  run it repeats. Those rows live on that run and on the ones before it,
  never on the resume itself. See
  [[docs/explanation/resume-stage-history-walk.md|Resume stage history walk]].
- State-machine transitions fire the `after_transition` / `after_commit`
  callbacks declared on `LegislationPipelineRun` / `PipelineRunBill`, which
  handle audit logging and the ActionCable broadcast.
