---
mode: explanation
summary: "Explains why LegislationPipelineRun#reopen_stuck_stage! writes the status column directly instead of firing a state machine event."
status: agent-extracted
related: ["docs/explanation/resume-stuck-stage-reset.md"]
---
<!-- vale Vale.Spelling = NO -->

# Why reopen_stuck_stage! bypasses the state machine

`LegislationPipelineRun#reopen_stuck_stage!` puts a run whose worker was
killed mid-stage back into `:running`. It is the one status write on this
model that does not go through the state machine.

## Why no event fits

A worker that dies inside a stage leaves the row in a per-stage status
(`fetching_law`, for example). Every event that leaves such a status —
`complete_extract_text` and its six siblings — means "this stage
finished". None of those is true here, and firing one would also mark the
matching `pipeline_run_stages` row succeeded, which is exactly the row the
caller then has to reopen. No event exists for "nobody finished this; put
it back", so `reopen_stuck_stage!` writes the `status` column directly with
`update_columns`.

## What it has to do by hand

Writing the column directly skips the two things the state machine's
`after_transition` hook would otherwise do. `reopen_stuck_stage!` does both
of them itself:

- it calls `PipelineActivityLogger.emit_state_transition!`, so the
  guarantee that no state transition lands without a matching Activity Log
  row still holds for this write;
- it calls `broadcast_status_change`, so the operator's screen does not sit
  on the stuck status until something else happens to trigger a broadcast —
  which, on a surface that must never ask for a manual refresh, is the same
  as never.

## The event name

The event name passed to the activity log is `"reopen_stuck_stage"`, the
method's own name, not one of the state machine's event names, because no
state machine event happened. A reader of the Activity Log should be able
to tell a stage that completed from a stage that was abandoned and
reopened.
