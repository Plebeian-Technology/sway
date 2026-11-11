---
mode: explanation
summary: "What Pipeline::ArtifactPresence checks, who calls it, and the two artifact locations that are easy to get wrong when adding a stage."
status: agent-extracted
related: [pipeline-preview-service-design, legislation-path-segment-safety]
---

# Pipeline::ArtifactPresence overview

`Pipeline::ArtifactPresence` answers one question per pipeline stage: has
this stage already produced its output? There are 7 such checks, used by the
pipeline runner and by `PipelinePreviewService` (see
[pipeline-preview-service-design.md](pipeline-preview-service-design.md) for
why that service batches its calls into `Pipeline::ArtifactPresence.batch_for`).

## Two details that are easy to get wrong

1. **fetch-hearings writes one file per bill**, sitting directly in that
   bill's jurisdiction directory:
   `legislation/hearings/<sway_locale>/<external_id>.json`. It is not the
   nested `legislation/bills/hearings/<id>/hearings.json`. The `sway_locale`
   segment is required, not decorative — a `Bill` is unique on
   `(external_id, sway_locale_id)` together, so two jurisdictions sharing an
   `external_id` used to share one file. See
   [legislation-path-segment-safety.md](legislation-path-segment-safety.md).
2. **summarize-bill reads `bill.bill_llm_provisioning&.llm_summary`.** There
   is no `summary_markdown` column; the real column is `llm_summary`.

## The batched lookup

`Pipeline::ArtifactPresence.batch_for` is the batched form of the same
checks. The preview screen calls it once per render and reads the Hash it
returns, which is what keeps the preview under 100ms with 166 bills on the
page.

`batch_for` returns `Hash[bill_external_id => Hash[stage_key => bool]]` for
the 6 per-bill stages. `fetch-law` is run-level and OMITTED — callers use
`present?("fetch-law", bill: nil)` separately.

`batch_for` is meant to collapse roughly 1,000 DB hits plus 166-332
filesystem stats down to 3-4 round-trips at 166-bill scale: one eager-load
query, two grouped parse-sections queries, two filesystem globs. Only the
eager-load claim is spec-checked (`artifact_presence_spec` asserts
`includes` is called with `:bill_llm_provisioning`) — the rest are
unverified claims, not guarantees.

## Why present? takes a bill: keyword even for the one run-level stage

`#present?` checks one bill and one stage. `fetch-law` is the one run-level
stage among the 7 — its `bill:` keyword is accepted but ignored, so callers
can iterate over the same stage list without special-casing the run-level
one. The other six stages are per-bill and return `false` when `bill` is
`nil`, a defensive guard rather than an expected call shape.

An unknown `stage_key` raises `ArgumentError` rather than returning `false`:
failing closed means a typo'd or renamed stage key surfaces immediately as
an error, instead of quietly reading as "not present" everywhere it is
checked.

## Why parse-sections has a secondary signal

`#present?("parse-sections", ...)` and `batch_for`'s parse-sections check
both ask "did this stage conclude for this bill?", not "does an artifact
exist?" A non-amending bill's legitimate outcome is zero
`BillSectionReference` rows; an artifact-only check flagged those as
"missing" forever. `stage_results` (on `PipelineRunBill`) is consulted as
a secondary signal: `succeeded` or `skipped` both count as not-applicable,
but a `failed` status still returns false, since an operator alert remains
appropriate for a real failure.
