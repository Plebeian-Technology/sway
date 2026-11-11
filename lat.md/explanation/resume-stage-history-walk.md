---
lat:
  mode: explanation
---

# Why succeeded_stage_names_before walks the whole resume chain

`RunLegislationPipelineJob#succeeded_stage_names_before` returns every stage name that has already succeeded for the run a resume repeats.

## It reads the runs before this one, never this one

This used to read `run.pipeline_run_stages`, where `run` is the row `LegislationPipelineRunService#resume` has just created.

That row is new and has no stages, so the set was always empty, nothing was ever skipped, and resume re-ran every stage. On a run with `summarize` checked, that meant buying the summary call and the positions call again, for every bill in the run — the one thing resume exists to avoid.

Nothing could catch it, because every fixture builds the new run the same way. The reader and the rows it should have read never disagreed.

## It walks the whole chain

A resume of a resume has a parent that is itself a resume, and that parent only holds the stages its own attempt completed. Take a run that finishes stages 1 to 3 and fails at 4. The first resume finishes 4 and 5 and fails at

6. Its own parent link names only the first run, so a second resume that

read one level up would re-run 1 to 3 and pay again.

The walk is bounded by the number of runs already visited, so a `parent_run_id` that points at itself, or a cycle written by hand, stops rather than looping.

## Why parent_run_id points backward at all

Resuming or restarting a run creates a new `LegislationPipelineRun` row that points back to the original via `parent_run_id`, rather than mutating the original row in place, so the resume/restart history stays auditable.

## The rest of the audit trail in to_builder

`LegislationPipelineRun#to_builder` surfaces the resume/restart audit trail (`parent_run_id`, `origin`) in the Inertia payload; the React UI (`BillCreatorPipelineControls.tsx`) reads these directly.

A `summary` field used to ride along here too, but nothing ever wrote that column — its webhook died with the Python sidecar it belonged to — so it was always `nil`. Serializing it just taught the frontend to render a fact that did not exist. The column and its dead twin `bill_count` are now gone from the table entirely.

## Why the "filters out stages the resumed run already finished" fixture puts the succeeded row on the PARENT run

The succeeded stage row in this spec belongs to the run being RESUMED, not to the resume run itself.

An earlier version of this example put the succeeded row on the resume run (`run`) and passed — that is the exact shape needed to hide the bug `succeeded_stage_names_before` walks around above: `LegislationPipelineRunService#resume` creates the resume row fresh, with no stages at all, so in production the set the old, buggy code read was always empty and nothing was ever skipped. That fixture was the one state in which the wrong read happened to give the right answer, so nothing could catch the regression. The corrected fixture attaches the succeeded `PipelineRunStage` to the PARENT run instead, matching what production actually creates.
