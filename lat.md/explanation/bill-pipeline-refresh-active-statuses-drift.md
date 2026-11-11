---
lat:
  mode: explanation
---

# The bill_pipeline_refresh drift

`bill_pipeline_refresh` is the prop the Bill Creator's four buttons that cost money use to decide whether to grey themselves out.

For a while no request spec covered it at all, which is how its query drifted away from the model's own list of statuses without anything noticing.

## What went wrong

The query asked for `"queued"` and `"running"` only, so a run in one of the seven per-stage statuses — where a run spends most of its life — left the prop `nil`.

A `nil` prop reads as "not busy": the busy notice disappears, every button comes back to life mid-run, and `GenerateBillSummaryService`'s own check still reports the summary as completed. One click then pays for a second model call, racing the pipeline's own summarize stage.

## The fix

`LegislationPipelineRun::ACTIVE_STATUSES` already existed for this, and its own comment already records the same lesson learned elsewhere: a two-status filter reports a busy run as free. It had simply never been used here.

## Why ACTIVE_STATUSES must include the per-stage states

`ACTIVE_STATUSES` is also what `PipelineRunsController` uses to reject duplicate Run Pipeline submissions.

The per-stage `*ing_*` states must be included: a run currently `fetching_law` (or in any other mid-stage status) is still active. A filter that only checked `queued`/`running` would report it as done, and the next enqueue would trip Solid Queue's `on_conflict: :raise` and show the operator a 500 error instead of a clean 409 "already running" response.

## Why the "Pipeline failed" alert needed its own prop

The summary tab's "Pipeline failed" alert had never rendered, because it was gated on a status `bill_pipeline_refresh` cannot deliver.

The summary tab's "Pipeline failed" alert had never rendered, because it was gated on a status `bill_pipeline_refresh` cannot deliver: `bill_pipeline_refresh` holds only ACTIVE runs, and `failed` is deliberately not an active status. So the operator's only message about a failed run was "Run the legislation pipeline for this bill first" — do the thing that just failed — with the actual reason sitting on a different tab. `bill_pipeline_last_failure` is the separate prop that carries the failed run's reason to the summary tab.

### Why the alert's remedy needs the failed run's own id

The alert's remedy said "open the Pipeline tab to resume or restart the run".

The alert's remedy said "open the Pipeline tab to resume or restart the run" — but that tab draws Resume and Restart for whichever run `LegislationPipelineRunSourcing` is SHOWING, chosen without any reference to this particular bill's failed run. The alert links to `?run_id=` instead, and `#explicitly_selected_pipeline_run` resolves that with a plain `find_by(id:)` — no cap, unlike the run selector's `RECENT_PIPELINE_RUNS_LIMIT` list, so an older failure is still reachable. Without the failed run's own id in this prop, that link cannot be built at all.

## Why active_any exists alongside active_global

`LegislationPipelineRun.active_any` matches any active run, whether single-bill or all-bills.

The orchestrator's concurrency key is global, so the controller's pre-enqueue gate consults this scope, not `active_global`, when deciding whether to reject a new POST.
