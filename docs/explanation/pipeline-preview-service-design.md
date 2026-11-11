---
mode: explanation
summary: "Explains why PipelinePreviewService walks stage dependencies through Pipeline::StageDeps, how it trims auto-included stages, and why it batches its one presence query."
status: agent-extracted
related: [docs/reference/pipeline-preview-reply-shape.md]
---
<!-- vale Vale.Spelling = NO -->

# Why PipelinePreviewService is built this way

`PipelinePreviewService` works out, in Ruby, which pipeline stages an
operator's selection will actually run before they press the button. It
used to be a call out to a Python service that no longer exists in
production; now it is plain Ruby. The stage picker in the Bill Creator
(`PipelineStageSelector.tsx`) receives the answer as the `pipeline_preview`
prop. For the shape of that answer, see
[pipeline-preview-reply-shape.md](../reference/pipeline-preview-reply-shape.md).

## Dependencies are walked, not approximated

Stages depend on each other: `parse-sections` needs extracted text, and so
on. To decide what really runs, the service walks those dependencies all
the way back through `Pipeline::StageDeps.transitive_closure` — the same
helper the pipeline runner itself uses, so there is only one copy of the
rules. An earlier version guessed by taking every stage from the start of
the fixed stage order up to the last one selected, which was only an
approximation.

## What happens to a pulled-in dependency

With "download missing assets" turned on, a dependency the operator did not
tick is dropped again if every bill in scope already has the file or column
that stage would produce — there is no point re-running work already done.

With it turned off, nothing extra is added. Instead the reply carries the
`prereq_violations` list described in the reference doc, which the stage
picker turns into a warning.

## One batched query, not one per bill

Speed matters here: `Pipeline::ArtifactPresence.batch_for` is called at
most once per request, and the hash it returns is read in memory for both
the dependency trimming and the warnings. With 166 bills that turns roughly
a thousand separate database hits into about three queries per render.

With no bills to look at, `#fetch` uses an empty presence map and skips the
per-bill trimming entirely rather than calling `batch_for` with nothing to
ask about. `compute_prereq_violations` reuses that same batch rather than
querying again, so it costs no extra database queries either.

## Why DAG_ORDER borrows LegislationPipelineRun's stage order

`DAG_ORDER` is `LegislationPipelineRun::ALLOWED_PIPELINE_STAGES`, so there
is one canonical stage order, not two. It is used only to sort the result
of `Pipeline::StageDeps.transitive_closure` back into display order — which
stages belong in the set is decided by that walk, and the walk visits them
in whatever order it happens to reach them, not in run order.

## Why an unknown stage name returns nil rather than an error

The old Python service rejected unknown stage names, and the client
quietly turned that rejection into `nil`. `#fetch` does the same: when the
preview cannot be built the picker just hides the "these will run too" box,
and the operator is not shown an error.

## The fetch-law exception to per-bill presence data

`Pipeline::ArtifactPresence.batch_for` covers six stages, one entry per
bill. `fetch-law` is left out because it produces a single file for the
whole run, not one per bill, so it never appears in the per-bill data.
Both `compute_will_run`'s trimming and `compute_prereq_violations`'s
warnings ask the same `per_bill_stage?` question, so they cannot disagree
about which stages have per-bill evidence — and when there is no data, or
none for `fetch-law` specifically, both play it safe and keep the stage
rather than drop it.
