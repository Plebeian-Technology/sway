---
lat:
  mode: reference
---

# Stages-to-run algorithm

See also: [[docs/explanation/stages-to-run-history.md|Why stages_to_run reads run.stages]] for the history behind why this reads the operator's selection instead of returning every stage.

- `RunLegislationPipelineJob#stages_to_run` turns the operator's "Stages to run" checkboxes into the actual list of stages to execute.

## What it does

Resolution logic transforming requested stage identifiers into ordered executable pipeline tasks.

- Translates `run.stages` hyphenated keys (`"fetch-bills"`) to internal
  symbols via `Pipeline::StageKeys.to_symbol`. A bogus operator-supplied
  stage raises `KeyError` right here rather than slipping through.
- If `run.download_missing_assets` is `true`, pulls in each selected stage's
  prerequisites via `Pipeline::StageDeps.transitive_closure` (the shared
  helper — this is not reimplemented locally) and unions that with the
  literal selection. Closure minus selection is the auto-included set
  (`Pipeline::Current` carries it forward to the activity logger; see the
  per-stage loop in `#perform`).
- If `run.download_missing_assets` is `false`, uses the literal selection
  as-is. A per-bill stage running without its prerequisite artifact raises
  `BillProcessingError` inside the per-bill loop, which counts toward
  `CONSECUTIVE_FAILURE_BUDGET`.
- Orders the candidate set by `DAG_ORDER`.
- On resume, additionally drops stages whose `pipeline_run_stages` row is
  already `"succeeded"`.

## Where the artifact-aware skip lives

The artifact-aware skip itself lives in `run_bill_level_stage` and only applies to auto-included stages. Operator-checked stages always run for every bill in the run — the artifact-aware gate is bypassed for them entirely.
