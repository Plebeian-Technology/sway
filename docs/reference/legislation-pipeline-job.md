---
mode: reference
summary: "Documents how RunLegislationPipelineJob behaves: its concurrency limit, stage looping, failure budget, resume mode, and callback-driven side effects."
status: agent-extracted
related: []
---
# RunLegislationPipelineJob behavior

<!-- vale Vale.Spelling = NO -->

`RunLegislationPipelineJob` is the one background job that runs the whole
legislation pipeline — fetching bills, extracting text, summarizing, and so
on — on Solid Queue.

## How it behaves

- `limits_concurrency to: 1, on_conflict: :raise` — at most one
  `RunLegislationPipelineJob` is ever active, anywhere. A second enqueue
  raises so the caller (`BillsController`, a manual trigger, etc.) can return
  HTTP 409 ("already running"). See
  [Legislation pipeline concurrency layers](legislation-pipeline-concurrency-layers.md)
  for the full locking design.
- `RUN_LEVEL_STAGES` (`fetch_bills`, `fetch_law`) run exactly once per run.
- `BILL_LEVEL_STAGES` loop over `run.pipeline_run_bills`. Each bill's outcome
  is written to the `pipeline_run_bills.stage_results` JSON column. See
  [Pipeline bill stage status model](../explanation/pipeline-bill-stage-status-model.md)
  for what the possible outcomes mean.
- A bill-level stage aborts after 5 bills fail in a row
  (`CONSECUTIVE_FAILURE_BUDGET`).
- Resume mode (`origin: "resume"`) skips stages that already succeeded on the
  run it repeats. Those rows live on that run and on the ones before it,
  never on the resume itself. See
  [Resume stage history walk](../explanation/resume-stage-history-walk.md).
- State-machine transitions fire the `after_transition` / `after_commit`
  callbacks declared on `LegislationPipelineRun` / `PipelineRunBill`, which
  handle audit logging and the ActionCable broadcast.
