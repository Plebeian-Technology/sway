---
mode: explanation
summary: "Why RunConflictBanner reads active_legislation_pipeline_run rather than the pinned run, why cancel-safety belongs to BillCreatorShell, and how isQueued/isAbandoned/description are derived after the terminal-status early return."
status: agent-extracted
related: [docs/explanation/pipeline-progress-panel.md]
---
<!-- vale Vale.Spelling = NO -->

# RunConflictBanner mechanics

## Why current_stage is not on ILegislationPipelineRun here

No `current_stage` here on purpose: it is null for a run that has started
but not reached its first stage, so `status` is the only column that
answers "has it started".

## Why bill_external_id is read off the linked Bill

The bill number a person would recognise for the bill this run covers.
LegislationPipelineRun#to_builder reads it off the linked Bill.

## Why abandoned defaults to "attended" when absent

Whether any worker is still carrying this run. The server decides it;
absent reads as attended.

## Why there is no cancelled_at field here

No `cancelled_at` here on purpose — the table has no such column, only
`completed_at`. Add it to to_builder AND the database first if a screen
ever needs one.

## Why onCancelRun's cancel-safety lives in BillCreatorShell

Safety-to-cancel belongs to BillCreatorShell, not here — same
isCreatorDirty check every nav on this screen uses; the server's redirect
can land elsewhere mid-edit.

This component only decides WHETHER the operator meant to cancel (two-tap
confirm); onCancelRun decides if that's allowed right now.

## Why the banner reads active_legislation_pipeline_run, not the pinned run

The banner warning an operator that a pipeline run is already in
progress, drawn above the tabs by BillCreatorShell.

Reads active_legislation_pipeline_run, not legislation_pipeline_run — it
always names the run truly in flight, even under a pinned ?run_id=
showing a different run.

Cancel reuses the existing DELETE /bills/legislation_pipeline_runs/:id
route.

## Why isQueued treats a null status as queued, not "in progress"

After the early return above, status is one of queued, running, or a
per-stage name — every terminal status has already been dropped.

A null status reads as queued, not "in progress": the type allows null
even though the DB defaults to "queued" — queued is the weaker claim,
matching a null started_at.

## Why isAbandoned is checked before isQueued

Checked before isQueued: a run can be abandoned in any non-final status,
queued included.

## Why billLabel/description avoid promising a wait time

Not "starting soon" — a queued run can sit long enough to become an
orphan (see handleDeleteOrphans in usePipelineRunActions). Only the
condition is provable, not the wait.

Deliberately promises no clear-up time: the job that closes these lives
in the worker that stopped.

## Why the AlertTitle must stay tied to the same branch as the description

Must stay tied to the same branch as the description below — they
contradicted each other when this was unconditional.

## Why the Cancel button reuses the same endpoint for a live run and an abandoned one

Same endpoint either way. "Cancel" reads as stopping work in flight; for
an abandoned run there is none. See
[pipeline-progress-panel.md](pipeline-progress-panel.md) — PipelineProgress's
Cancel button follows the same rule.
