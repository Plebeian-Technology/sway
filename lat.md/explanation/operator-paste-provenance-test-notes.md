---
lat:
  mode: explanation
---

# Test-design notes for OperatorPasteProvenance.test.tsx

Explains OperatorPasteProvenance.test.tsx's scope (the stale header's regenerate button and the provenance chip) and its fixture that disagrees llm_provider and paste_owns_summary_run on purpose.

## File scope

The completed branch renders `PasteSummaryDialog` and `LlmSummaryEditableSummary`, reading Inertia's props and router. This file is about the out-of-date header's button and the provenance chip.

## Why this scenario is tested (the destructive-unconfirmed-click bug)

A pasted summary is out of date FOREVER: `PasteSummaryService` stamps `llm_generated_at` once, and every later pipeline run only pushes it further stale.

The out-of-date header's regenerate button fired unconfirmed, destroying hand-written text the interface never labeled as hand-written.

That same button also ignored `isBillPipelineRunning` — the one regenerate control that fired a paid POST while the interface said generation was unavailable. See [[docs/explanation/bill-creator-stale-header-layout.md|bill-creator-stale-header-layout.md]] and [[docs/explanation/pipeline-busy-terminal-status-inversion.md|pipeline-busy-terminal-status-inversion.md]] for the fixes these examples pin.

## Fixture notes

A settled paste carries both columns: `PasteSummaryService` writes the body, the provider name and the marker in one update, and nothing on the way to `completed` clears the marker.

Both paste columns have to come off together here, or this fixture would be a row no writer produces: a model body under a paste marker.

## Why one fixture disagrees the two paste columns

`llm_provider` and `paste_owns_summary_run` move together in every fixture above. A pasted-then-stalled row disagrees on the two — the only row telling apart a chip reading each column.

The chip must read `llm_provider`, not `paste_owns_summary_run`. This fixture disagrees on the two columns, which is the only way to tell them apart. See [[docs/explanation/llm-summary-in-flight-notice.md|llm-summary-in-flight-notice.md]] for the backend rule these two columns follow.

## Why the destructive-click example matters

The out-of-date header's button is the ONLY regenerate button on an out-of-date row, and it destroyed unrecoverable work on a single click.

## Model-generated stale rows get different confirmation copy

A model-generated stale row gets the same confirmation, with copy that does not claim work was hand-written.

## The pipeline-ignoring generate button

The one generate button that used to ignore the pipeline.
