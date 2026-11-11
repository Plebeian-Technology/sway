---
lat:
  mode: explanation
---

# Pipeline::ArtifactPresence overview

`Pipeline::ArtifactPresence` answers one question per pipeline stage: has this stage already produced its output?

There are 7 such checks, used by the pipeline runner and by `PipelinePreviewService` (see [[docs/explanation/pipeline-preview-service-design.md|pipeline-preview-service-design.md]] for why that service batches its calls into `Pipeline::ArtifactPresence.batch_for`).

## Two details that are easy to get wrong

Two subtle implementation details in pipeline artifact layout: flat jurisdiction directories and separate raw PDF storage paths.

1. **fetch-hearings writes one file per bill**, sitting directly in that
   bill's jurisdiction directory:
   `legislation/hearings/<sway_locale>/<external_id>.json`. It is not the
   nested `legislation/bills/hearings/<id>/hearings.json`. The `sway_locale`
   segment is required, not decorative — a `Bill` is unique on
   `(external_id, sway_locale_id)` together, so two jurisdictions sharing an
   `external_id` used to share one file. See
   [[docs/explanation/legislation-path-segment-safety.md|legislation-path-segment-safety.md]].
2. **summarize-bill reads `bill.bill_llm_provisioning&.llm_summary`.** There
   is no `summary_markdown` column; the real column is `llm_summary`.

## The batched lookup

`Pipeline::ArtifactPresence.batch_for` is the batched form of the same checks. The preview screen calls it once per render and reads the Hash it returns, which is what keeps the preview under 100ms with 166 bills on the page.

`batch_for` returns `Hash[bill_external_id => Hash[stage_key => bool]]` for the 6 per-bill stages. `fetch-law` is run-level and OMITTED — callers use `present?("fetch-law", bill: nil)` separately.

`batch_for` eager-loads `:bill_llm_provisioning`, preloads `:sway_locale`, runs two grouped parse-sections queries, and checks target bill paths directly for small batches (`<= 10` candidate keys) or scopes its PDF and hearing directory globs to the locales present in the batch for larger sets.

## Why present? takes a bill: keyword even for the one run-level stage

`#present?` checks one bill and one stage.

`fetch-law` is the one run-level stage among the 7 — its `bill:` keyword is accepted but ignored, so callers can iterate over the same stage list without special-casing the run-level one. The other six stages are per-bill and return `false` when `bill` is `nil`, a defensive guard rather than an expected call shape.

An unknown `stage_key` raises `ArgumentError` rather than returning `false`: failing closed means a typo'd or renamed stage key surfaces immediately as an error, instead of quietly reading as "not present" everywhere it is checked.

## Why parse-sections has a secondary signal

Both `#present?("parse-sections", ...)` and `batch_for` check whether the stage concluded for the bill, not only whether section references were written.

`#present?("parse-sections", ...)` and `batch_for`'s parse-sections check both ask "did this stage conclude for this bill?", not "does an artifact exist?" A non-amending bill's legitimate outcome is zero `BillSectionReference` rows; an artifact-only check flagged those as "missing" forever. `stage_results` (on `PipelineRunBill`) is consulted as a secondary signal: `succeeded` or `skipped` both count as not-applicable, but a `failed` status still returns false, since an operator alert remains appropriate for a real failure.

## Cleaned-testimony freshness and letter offsets

A cleaned testimony artifact is fresh only when `cleaned_testimony_at` is at or after `testimony_fetched_at`, and each letter's character offset indexes into the cleaned text rather than the raw column.

`cleaned_testimony` describes `extracted_testimony` as it stood at `cleaned_testimony_at`, written by [[app/services/testimony/clean_and_group_service.rb#CleanAndGroupService]]. Once `testimony_fetched_at` moves past that timestamp, a later fetch run may have replaced the raw column with text the cleaning stage never saw, so readers such as [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] and [[app/models/pipeline/artifact_presence.rb#ArtifactPresence]] compare the two timestamps before trusting the artifact and treat an older `cleaned_testimony_at` as stale. A bill with no `testimony_fetched_at` yet reads a present `cleaned_testimony_at` as fresh because no later fetch has superseded it.

Within a fresh artifact, `cleaned_testimony["letters"]` describes `cleaned_testimony["text"]` — the character-repaired, banner-stripped text. Each entry's `character_offset` is an offset into that cleaned string, never into `extracted_testimony`, because character repair and banner removal change the string length and would land a raw-column offset on the wrong letter.
