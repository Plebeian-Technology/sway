---
mode: explanation
summary: "Explains why PipelineRunBill#status is a coarse per-bill summary rather than live per-stage state, and where the real per-stage data lives."
status: agent-extracted
related: [pipeline-bill-stage-status-model.md]
---

<!-- vale Vale.Spelling = NO -->

# PipelineRunBill's status column is a coarse summary

`PipelineRunBill#status` is one coarse summary for the whole run, not a live
per-stage status. Once the FIRST stage to handle a bill succeeds, `status`
stays `"succeeded"` for the rest of the run, even while later stages —
`extract_text` → `parse_sections` → `generate_diffs` → `fetch_hearings` →
`summarize` — are still working on that bill. The orchestrator's
`can_start_running?`/`can_mark_succeeded?` guards quietly no-op the rest of
the state machine once that first success lands.

The real per-stage state lives in the `stage_results` JSON column, surfaced
to operators via `pipeline_activity_log_entries` (`subject: bill_run`) —
never from `status`. A future live per-stage screen must read
`stage_results`, not `bill_run.status`.

Do not change this meaning without checking every reader of
`bill_run.status` in the orchestrator and serializers first.
