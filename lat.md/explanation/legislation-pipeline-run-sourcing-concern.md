---
lat:
  mode: explanation
---

# LegislationPipelineRunSourcing

Adds `legislation_pipeline_run` and `stale_pipeline_run_count` (plus three sibling props) to every Inertia response from any controller that includes this concern.

Those props feed both the "a run is already going" banner and the disabled state of the Run button, so every Bill Creator tab agrees about what is running. The banner survives moving between tabs because these props are merged into EVERY Inertia response from `BillsController`, not only the edit action.

## Why the admin check runs before anything else

Without the `current_user&.is_sway_admin?` check in `inertia_share`, pipeline details.

Without the `current_user&.is_sway_admin?` check in `inertia_share`, pipeline details — status, current stage, error messages — would ride along on every public bill page, including ones served to signed-out visitors, and cost two extra database queries per page load. Only the admin Bill Creator screens read these props.

## Why legislation_pipeline_run_props reads active_any, not active_global

This MUST use `active_any`, not `active_global`.

The checks in `BillsController` that decide whether a new run may start also use `active_any`, so a single-bill run in flight blocks an all-bills request. With the narrower scope here, that request would be refused while the admin saw no banner, no count, and no sweep button — the running single-bill job would be invisible to them. `active_any` covers both single-bill and all-bills runs, matching what the controller checks.

## Why each prop is a lambda

Each value in `legislation_pipeline_run_props` is a lambda reading one snapshot taken per request.

A partial reload that asks for none of these props — the admin Bill page's score-only refresh, for instance — never calls a lambda and so runs zero pipeline queries. Inertia only calls the props a partial reload asks for; on a full page load all five run and share the same snapshot.

`recent_pipeline_runs` fills the dropdown, so an admin can inspect any run, not only the one picked by default. `stale_pipeline_run_count` covers only runs still in flight; a run that has already finished needs no sweep button.

For `active_legislation_pipeline_run` and why it is a separate prop from `legislation_pipeline_run` rather than the same value, see [[docs/explanation/pipeline-run-pin-vs-active-run.md|Why the pinned run and the active run are two different props]]. The newest run still in flight is nil when nothing is running, the same as `legislation_pipeline_run` when there is no explicit selection and nothing has ever run.

## Why the snapshot is computed once per request

`pipeline_share_snapshot` memoizes: all five props read this same snapshot, so they cannot disagree — a run finishing halfway through a request cannot leave the banner showing a run while the count says zero.

The `||=` means none of this work happens when no pipeline prop is asked for.

Inside `compute_pipeline_share_snapshot`, each run's bills and stages are loaded up front, so the per-bill grid costs one query total rather than one per row on an all-bills run. The active runs are pulled into an array once so `surfaced_run` and `stale_pipeline_run_count` both derive from the same snapshot — querying twice risks a run finishing between the two queries, leaving the banner showing a run while the count says zero.

## Why orphan_pipeline_run_count is a separate button from the sweep

`orphan_pipeline_run_count` feeds the separate "Delete N orphan run(s)" button.

Orphan and stale are not the same thing: stale means queued or running right now, and the sweep button marks those failed; orphan means queued or running for more than four hours with no background job left tracking it, and those are deleted outright. Keeping the two buttons apart gives admins a safe recovery action and a separate, deliberate destructive one. See LegislationPipelineRun orphan detection for the underlying checks.

## Why surfaced_pipeline_run falls back to successful runs

Which run the Bill Creator pipeline screen shows, in order:

1. A run named by `?run_id=` — the dropdown — always wins, so an admin can
   pin any past run, a successful one included.
2. Otherwise the newest run still in flight; work happening now comes
   first.
3. Otherwise the newest run of any status, successful ones included.

Step 3 has to include successful runs. Falling back only to failed ones leaves the screen showing the last failure — its old error banner and its stuck bills — even after a later run succeeded. The Resume and Restart controls look at the shown run's own status, so a successful run shows neither, and any failed run is still reachable from the dropdown.

## Why recent_pipeline_runs_summary eager-loads bills

Each run's bill is loaded along with it, so labelling a single-bill run does not cost one query per row — the Bullet checker that watches for that has to stay quiet.
