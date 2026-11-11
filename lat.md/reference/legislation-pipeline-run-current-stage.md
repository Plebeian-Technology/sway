---
lat:
  mode: reference
---

# LegislationPipelineRun.current_stage

`current_stage` is a denormalized column kept in step with the status state machine by a `before_transition` hook. `to_builder` sends it, and screens that name which stage a run is inside read it from there.

- `current_stage` is looked up from `STAGE_STATUS_TO_DAG_NAME`, keyed by the transition's target status. `queued -> running` maps to no DAG name, so the hook writes nothing for that transition, and the column stays `nil` through `pre_seed_single_bill_pipeline_run_bill!`, `hydrate_pipeline_run_bills_from_disk!`, and the dependency-graph closure.

## What it does not answer

`current_stage` does not answer "has this run started?" `RunConflictBanner` used to read it for that question and label all of the states above as "queued".

- It reads `status` now. The `.from(nil)` assertions in `legislation_pipeline_run_spec.rb`'s "stage tracking via state-machine transitions" examples are the proof that this column cannot answer that question on its own: the fixture there has already called `start_running!`, and the stage is still `nil` at that point.

- Before `current_stage` and the `pipeline_run_stages` rows were kept in step with the state machine, both stayed blank even while a run was actively moving through stages, so the per-bill grid header showed "Stage —, Stages 0/0" for a run that was working.

## Behavior on terminal statuses

No transition into a terminal status (`:succeeded`, `:failed`, `:cancelled`) clears `current_stage`.

- `STAGE_STATUS_TO_DAG_NAME` has no entry for any terminal status, so the hook's `if dag_name` guard leaves the column holding whichever stage ran last.

- This is deliberate. On a failed run, the last stage named there is what `PipelineActivityLogger` reads to log which stage failed (see `run_legislation_pipeline_job.rb`). Read `status` to know whether a run is still active; read `current_stage` on a terminal run to see its last stage, not its current one.

### PerBillGrid's test rendering note

Only the pinned row's badge (HB001, "pending") actually renders — the rest sit in the virtualizer, which the fake browser never paints.

### PerBillGrid's test for the finished-run Stage column

current_stage is never cleared when a run ends — kept on purpose to show where a failed run died — so a finished run could still show a stage that reads as in-progress.

- Each case below sets the two columns to values that contradict each other: a stage name that is really there, next to a status saying the run is over.

### RunConflictBanner's test for which column decides "has the run started"

The old fixtures moved status and current_stage together, so nothing told the two columns apart — the banner read the wrong one.

- Production actually reaches {running, null} — before_transition only sets current_stage for DAG-stage transitions, and queued->running isn't one.

- The two examples below differ in exactly ONE field, so they answer which column the wording comes from.

### RunConflictBanner's test for an unvalidated null status

status: null is reachable at runtime — page props are unvalidated JSON — even though the db column is NOT NULL.

- The unknown state must not get the sentence that claims the run has started and offers a start time. It gets the weaker one.

## Why the write happens inside before_transition

The `current_stage` write runs in the state machine's `before_transition` hook so it rides the same UPDATE that changes `status` — one atomic write, not two.

## Why completed_at is stamped in the same hook

`completed_at` is stamped on the same UPDATE that lands the terminal status, so `PipelineTerminalAlerts` and the runs index stop reading a column nobody ever wrote.

- The write is guarded on `nil` so a run that is somehow re-saved in a terminal state does not overwrite the original finish time.

- Before this, nothing in the app wrote `completed_at` at all — `PipelineTerminalAlerts` showed "Cancelled at —" forever and the runs index Completed column was permanently blank. Every event that leaves a run in a terminal status must stamp it on that same transition; `legislation_pipeline_run_spec.rb`'s "completed_at stamped on terminal transitions" examples cover one example per terminal event, guarding against a sibling event sharing the same gap. Its "splits every status into exactly one of finished or not finished" example pins the two hand-written lists (`TERMINAL_STATUSES` and `PHASE_52_NON_TERMINAL_STATES`) against the fault this phase kept finding: a status added to neither list falls in the gap, meaning a finished run that never gets a finish time.
