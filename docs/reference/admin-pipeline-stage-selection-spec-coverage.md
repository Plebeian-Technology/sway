---
mode: reference
summary: "What spec/system/admin/creator/pipeline_stage_selection_spec.rb exercises end to end, and the data-testid values it depends on verbatim."
status: agent-extracted
related: [pipeline-controls-state-url-contract.md, pipeline-stage-selection-request-params.md]
---

# Admin pipeline stage selection spec: coverage and test-id catalog

`spec/system/admin/creator/pipeline_stage_selection_spec.rb` is an
end-to-end system spec that follows an admin from click to pipeline run to
ingest, through the Bill Creator's Pipeline & LLM tab.

## Pieces it proves work together

- `Pipeline::StageKeys` and `StageDeps`
- `Pipeline::ArtifactPresence`
- the `download_missing_assets` column, passed down through the services
- the orchestrator's `stages_to_run` honoring `run.stages` and
  `download_missing_assets`
- `PipelinePreviewService`'s `prereq_violations`, plus following
  `STAGE_DEPS` out to every stage a selection implies
- the front-end checkboxes, the download-missing-assets toggle, the
  prerequisite warning, and resume/restart
- the migration that dropped the old refresh column

## `data-testid` values used verbatim

These come from the UI design and must not be invented anew:

- `checkbox-stage-fetch-law` / `checkbox-stage-summarize-bill` /
  `checkbox-stage-*`
- `checkbox-download-missing-assets` (the toggle)
- `pipeline-prereq-warn-alert` (the prerequisite warning)
- `pipeline-auto-include-alert` (the "also required" notice)
- `btn-run-pipeline` / `btn-resume-pipeline` / `btn-restart-pipeline`

## Browser requirement

The system driver (`spec/support/system_driver.rb`) skips these examples
automatically when Chrome/chromedriver are missing from the test container,
printing the `SystemBrowserPreflight` message, rather than failing.

## Behavior 1: auto-included stages appear only when the run starts

The extra stages `STAGE_DEPS` implies for a selection are added later, when
the orchestrator runs, not when the form is submitted — this example proves
only that `LegislationPipelineRun` is saved with exactly what the operator
ticked plus `download_missing_assets`, not the expanded set.

## Waiting for a Radix Checkbox's redraw before the next click

A Radix Checkbox sets `data-state` to `"unchecked"` when it toggles.
Clicking a second checkbox before that redraw lands races the first
checkbox's own redraw under headless Chrome, and the first uncheck goes
missing from the POSTed stages every so often — the CI flake
`spec/system/admin/creator/pipeline_stage_selection_spec.rb`'s waits on
`data-state='unchecked']` between clicks fix. Missing this
wait let the "Run pipeline" click land while an uncheck was still in
flight, once observed as `expect(run.stages).not_to include("fetch-hearings")`
failing while a guarded uncheck earlier in the same example passed. The
server stores stages verbatim (`LegislationPipelineRunService#run!`), so a
stage on the row means the browser actually sent it.

## Clearing all stages: wait on the boxes, not the count

The stage-selection count is drawn from the same render as the buttons, so
it would agree with itself even if a click never reached a single checkbox
— the redrawn checkboxes are what has to be waited on. The clear-all
assertion also iterates `Pipeline::StageKeys::KEY_TO_SYMBOL` rather than a
restated list of stage keys, so a stage added later is covered by this
example without anyone remembering to update it.

## Behavior 2: the download-missing-assets toggle disables itself

When both fetch stages are checked, the toggle renders disabled. Both the
front end and the server enforce that independently, so neither one is a
single point of failure.

## Behavior 3: the prereq warning's wording lock and its own redraw race

The prerequisite warning's assertion insists on the exact "will FAIL"
phrasing so nobody softens it in a later edit. The warning depends on
`pipelinePreview.prereq_violations` arriving in the partial reload that
follows the toggle, which raced the admin system helpers' timing under
headless Chrome until an explicit wait for the toggle to become enabled
(`:not([disabled])`) was added — `disabled` is exactly `isRunning || both
fetch stages selected` (`PipelineStageSelector.tsx`), so its going away is
the proof that both preceding unchecks actually registered before the
toggle click that reveals the warning.

## Behavior 4: resume copies the parent's selection exactly

`btn-resume-pipeline` only renders when a current failed run reaches the
page as an Inertia prop, pushed over `PipelineRunChannel`. A resume copies
`parent_run.stages` and `parent_run.download_missing_assets` exactly; what
resume means server-side is covered in
`spec/services/legislation_pipeline_run_service_spec.rb#resume`, so this
example only proves the round trip from the click.

## Behavior 5: restart's discriminator value and its product gap

The `download_missing_assets` column defaults to `true` and the restart
POST sends no value, so a parent row left at the default `true` would pass
this example even with the inheritance code deleted — `false` is the only
value that can tell "inherited" from "defaulted" apart, which
is why the parent row here is built with it explicitly `false`.

The service allows a restart from any status, completed included, but the
failure-recovery panel offers no restart button on a completed run.
Whether it should is a separate product question, still open.
