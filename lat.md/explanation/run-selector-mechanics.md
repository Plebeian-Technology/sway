---
lat:
  mode: explanation
---

# RunSelector mechanics

Why RunSelector's dropdown pin lives in the ?run_id= query param read server-side by LegislationPipelineRunSourcing.

## Why picking a run sets ?run_id=

Dropdown for choosing which pipeline run to view. Defaults to the newest; older runs stay pickable, e.g. to compare a failure against the run before it.

Picking a run sets ?run_id= in the address, read server-side by LegislationPipelineRunSourcing. "Latest run (auto)" clears it, and the page follows the newest run again.

## Why RUN_SELECTOR_ONLY_PROPS asks for exactly these props

Rails works these values out again on every request, so asking for just these refreshes the shown run and the dropdown list under the new ?run_id=.

Without refreshing active_legislation_pipeline_run, RunConflictBanner (which reads the truly active run, not the pinned one) would keep answering for the previously chosen run.

## Why STATUS_GLYPH reuses the shared per-stage label map

Terminal/queued/running glyphs are this dropdown's own.

Per-stage entries come from the shared map in pipeline-controls/stages.ts (not copied), so wording matches the status badge. See [[docs/explanation/bill-creator-pipeline-status-badge-fallback.md|bill-creator-pipeline-status-badge-fallback.md]] for the badge side of that shared vocabulary.

## Why pinned checks the address, not just currentRunId

Counts as "pinned" only when ?run_id= is actually in the address — otherwise the page is following the newest run, even if currentRunId equals that run's id.
