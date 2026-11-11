---
mode: explanation
summary: "Explains the Pipeline::StageDeps module-naming split from Pipeline::STAGE_DEPS and the transitive_closure algorithm's termination and unknown-key handling."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Pipeline::StageDeps: why the graph and the module have different names

`Pipeline::STAGE_DEPS` is the pipeline stage dependency graph — which
stages need which other stages to run first, as directed acyclic edges. It
drives the breadth-first transitive closure used by the stage-checkbox
auto-include preview (UI) and by the orchestrator's `stages_to_run`
computation. This Ruby map is the source of truth; the TypeScript and RBS
copies are kept in sync by `spec/integration/stage_deps_sync_spec.rb`.

## Why EMPTY_DEPS carries a steep:ignore

`EMPTY_DEPS` is a shared frozen empty array (`[].freeze`), used by every
stage in `STAGE_DEPS` that has no upstream dependencies, so those stages
point at one shared object rather than each allocating its own empty
array. The `#: Array[String]` annotation and surrounding
`steep:ignore:start`/`steep:ignore:end` pair silence Steep's
`Ruby::UnannotatedEmptyCollection` warning while keeping the value frozen
and shaped like the populated `%w[...].freeze` arrays beside it.

## Why the constant and the module are named differently

Zeitwerk (Rails' autoloader) requires the file `pipeline/stage_deps.rb` to
define a constant named `Pipeline::StageDeps`. The graph data lives on the
separate `Pipeline::STAGE_DEPS` constant; `Pipeline::StageDeps` is the
module Zeitwerk autoloads when the file is first referenced.

The module holds `.transitive_closure(requested_keys)` — the single source
of truth for the dependency-closure computation, used both by the
orchestrator's `stages_to_run` and by
`PipelinePreviewService.compute_will_run`, so there are no duplicate
implementations to drift apart.

## transitive_closure's algorithm notes

`transitive_closure` does a breadth-first walk over `Pipeline::STAGE_DEPS`:
starting from `requested_keys`, it follows the dependency edges and
collects every stage reached. The output array is the visited set in
breadth-first order; downstream callers re-impose the canonical run order
via `DAG_ORDER`.

**Termination:** the graph is finite (7 nodes) and has no cycles by
construction. The `visited` Set is the cycle guard.

**Unknown keys:** an unrecognized key appears in the output but
contributes no further deps (`Hash#fetch` falls back to an empty array).
Rejecting bad keys is deliberately left to the parser seam
(`Pipeline::StageKeys.to_symbol`), not to this pure graph helper — keeping
the two concerns separate.
