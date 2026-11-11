---
lat:
  mode: reference
---

# Pipeline::StageDeps.transitive_closure

`Pipeline::StageDeps.transitive_closure` takes some pipeline stages and returns them plus everything they need, plus everything those need, all the way down. It walks the `STAGE_DEPS` graph one level at a time.

## Callers

Pipeline services and orchestrators that query transitive stage dependencies during execution planning.

- `RunLegislationPipelineJob#stages_to_run`, which decides what actually
  runs. See
  [[docs/reference/stages-to-run-algorithm.md|stages-to-run-algorithm.md]].
- `PipelinePreviewService.compute_will_run`, which shows an operator what
  would run.

## Walking the whole chain, not just direct dependencies

The easy mistake is stopping at the direct dependencies.

- The longest chain in the graph proves it keeps going: `summarize-bill` needs `generate-diffs`, which needs `parse-sections`, which needs `extract-text` and `fetch-law`, which need `fetch-bills`.

## An unknown stage key

A stage name that `STAGE_DEPS` has never heard of comes back in the answer but drags nothing along with it, because the lookup falls back to an empty list.

- Rejecting bad names happens earlier, where input is parsed (`Pipeline::StageKeys.to_symbol`), not in this graph helper.
