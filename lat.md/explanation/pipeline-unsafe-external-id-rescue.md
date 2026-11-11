---
lat:
  mode: explanation
---

# Why UnsafeExternalIdError is rescued in execute_bill_level_service

`RunLegislationPipelineJob#execute_bill_level_service` is the one place `Legislation::Paths::UnsafeExternalIdError` becomes a per-bill failure.

The error's own doc comment promises that "the pipeline entry points translate it" — `Legislation::Paths` sits below the pipeline and must not depend on it — but for a while nothing in `app/` or `lib/` rescued it. As a plain `StandardError` it fell through to the catch-all rescue, which raises `StageError` and force-fails the whole run. An `external_id` that cannot be turned into a safe path segment is a fact about one row; it says nothing about the other bills, so it belongs to the per-bill failure budget like every other single-bill failure.

## This one rescue covers every reachable raise

The six calls that can hit a raising `Legislation::Paths` builder are:

- `#execute_extract_text`'s `bill_text_file`
- `#locate_pdf`'s `bill_pdf_glob`
- `FetchHearingsService`'s `bill_metadata_file` and `hearings_file`
- `GenerateDiffsService::ResultWriter`'s `diff_json_file` and
  `diff_markdown_file`

Every one of them runs inside `execute_bill_level_service`, because the orchestrator is the only constructor of those services.

`FetchBillsService` (run-level) reaches its own two builders only with values already coerced by `external_id_segment`, so it needs no rescue: `#call_backfill_missing` bails on a nil `BillMetadata.matter_id` before the builder, and `#persist` is fed by `#build_metadata` / `#seed_from_disk`, both of which drop an unusable id.
