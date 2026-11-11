---
lat:
  mode: explanation
---

# Why stages_to_run reads run.stages

See also: [[docs/reference/stages-to-run-algorithm.md|Stages-to-run algorithm]] for what `RunLegislationPipelineJob#stages_to_run` computes today.

An older version of `stages_to_run` returned `DAG_ORDER` verbatim and ignored `run.stages` entirely — a leftover from the pre-Rails Python orchestrator, where the equivalent method had no per-run stage selection to honor. The operator's "Stages to run" checkboxes now flow all the way through, and `run.stages` is the source of truth for which stages a run actually executes.
