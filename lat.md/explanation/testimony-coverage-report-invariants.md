---
lat:
  mode: explanation
---

# Why the coverage digest includes state, and removed_chars clamps to zero

Why Testimony::CoverageReport's acknowledgement digest includes state, and why removed_chars clamps to zero instead of going negative when character repair adds more characters than the banner strip removed.

See [[distributed-testimony-pipeline]] for how reach and coverage gaps flow across `clean-testimony` and `summarize-bill`.

## The acknowledgement digest includes state

`Testimony::CoverageReport::Result#digest` fingerprints every field in `digest_fields`, including `state`.

A stage merely *starting* to run does not change any number the operator already read — the client already disables the acknowledge button while a run is in flight — but the same numbers can carry a different meaning depending on how they were produced. `:never_run` and `:failed` can report identical `total_chars`, `reached_chars`, `removed_chars` and `left_out_chars` (no clean-testimony pass ever completed in either case), yet they are not the same situation an operator signed off on: one means clean-testimony has never been attempted, the other means the last attempt errored out. Including `state` in the digest means an acknowledgement recorded under one does not silently cover the other. `spec/services/testimony/coverage_report_spec.rb`'s "the digest" example pins this: `never_run_result.digest` and `failed_result.digest` differ even though every other field matches.

## removed_chars clamps to zero; repair_added_chars is the separate growth field

"Removed as repeated" chars is `[total_chars - cleaned_chars, 0].max` — clamped to zero, not allowed to go negative.

The character-repair step can add a couple of characters back for every broken word it resolves, so a bill whose repair growth outweighs its (small or absent) banner could otherwise make this subtraction negative. Rather than let `removed_chars` carry that negative value, the growth is captured in its own field, `repair_added_chars` (`[cleaned_chars - total_chars, 0].max`), clamped the same way from the other direction. `removed_chars` is one of the three fields (`reached_chars`, `removed_chars`, `left_out_chars`) the `Result` docstring guarantees always sum to `total_chars`; letting it go negative would break that invariant, so the growth case is routed to `repair_added_chars` instead, which sits outside the sum.

## Why acknowledgements are keyed by bill and coverage digest

[[app/models/testimony_coverage_acknowledgement.rb#TestimonyCoverageAcknowledgement]] pairs a bill and an operator with the exact `coverage_digest` of the coverage numbers they reviewed, under a unique index on `[bill_id, coverage_digest]`.

[[app/services/acknowledge_testimony_coverage_service.rb#AcknowledgeTestimonyCoverageService]] is the only writer and [[app/services/testimony/coverage_report.rb#CoverageReport]] is the only reader that checks whether a stored row still matches the numbers on screen. The composite unique index on `[bill_id, coverage_digest]` guarantees at the database level that acknowledging the same coverage numbers twice leaves a single row, while any change to the underlying testimony or coverage state produces a new digest that requires a fresh acknowledgement.

## How CoverageReport computes call-time reach, freshness, and coverage gaps

[[app/services/testimony/coverage_report.rb#CoverageReport]] computes testimony reach and paste displacement at read time by delegating prompt budget arithmetic to [[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder#testimony_reach]].

Because operator-pasted testimony is never cleaned by the pipeline stage, computing the report on each read keeps paste displacement and budget figures current without re-running `clean-testimony`. `fresh_artifact_present?` requires `reach.source == :cleaned` so stale artifacts superseded by a later hearing fetch are reported as `:stale` rather than mixing old cleaned counts with live raw text. `coverage_gap?` flags `:failed`, `:stale`, uncleaned raw text (`:never_run` with positive non-paste characters), or any positive `left_out_chars` so single unsplit letters truncated mid-body still require operator acknowledgement.

## Preserving coverage invariants without false gaps from repeats or constituent letters

[[app/services/testimony/coverage_report.rb#CoverageReport]] preserves coverage invariants without false coverage gaps by having reach calculations credit letters filtered from the prompt.

`CoverageReport::Result` guarantees the invariants `reached_chars + removed_chars + left_out_chars == total_chars` and `reached_letters + removed_letters + left_out_letters == total_letters`. Because `left_out_letters` is computed as `total_letters - reached_letters` and `left_out_chars` as `cleaned_chars - reached_chars`, any letter omitted from `reached_letters` or `reached_chars` is classified as left out.

When `BillPositionsPromptBuilder` excludes constituent self-letters (`person_speaking_for_self`), repeated submissions (`repeat: true`), and manually excluded letters (`excluded: true`) from the organization-positions prompt, those letters are not unreached defects; they are handled by separate pipeline stages (such as stance classification, campaign draft grouping, and browsable testimony) or intentionally removed by an operator. If `#labeled_reach` omitted them from reach counts, `CoverageReport.coverage_gap?` would falsely flag every bundle containing constituent mail, duplicates, or manually removed correspondence as having dropped testimony.

`#labeled_reach` preserves the invariants by crediting excluded repeats, constituent self-letters, and manually removed letters in full to `reached_letters` and adding their raw character lengths to `reached_chars` without subtracting from the prompt character budget for nameable letters, while `CoverageReport#individual_letter_count` omits manually excluded letters from the individual constituent count. This allows `left_out_letters` and `left_out_chars` to remain at zero whenever all nameable letters fit within the prompt budget, ensuring coverage gap warnings occur only when genuine budget exhaustion or truncation takes place.

## Coverage invariants under windowing and multi-chunk partitioning

`Testimony::CoverageReport` preserves zero-gap coverage invariants across windowed letters and multi-chunk testimony bundles.

When individual letters exceed 12,000 characters, `#labeled_reach` treats the windowed letter as fully accounting for the source letter up to the per-chunk `max_testimony_chars` cap. Because the opening argument and signature block reach the model, `reached_chars` credits `[raw_body.length, max_testimony_chars].min`, ensuring `left_out_chars` remains zero while single unsplit letters exceeding `max_testimony_chars` still report the characters above `max_testimony_chars` as `left_out_chars`.

In multi-chunk bundles, `#labeled_reach` aggregates reached letters and characters across all chunks up to `max_positions_chunks`. A bundle of 32 letters totaling 160,000 characters partitions across 2 chunks, yielding `left_out_letters == 0` and `left_out_chars == 0`.

Coverage gaps occur only when genuine budget exhaustion takes place: when `llm_max_positions_chunks` is restricted to 1, or when a massive bundle exceeds all allowed chunks, the final chunk truncates and unreached letters are flagged for operator acknowledgement.

