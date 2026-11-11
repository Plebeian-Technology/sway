---
lat:
  mode: explanation
---
# Bill artifact write ordering

FetchBillsService commits database rows before writing artifact files to disk, ensuring partial failures remain observable and recoverable rather than crashing pipeline runs.

## Database rows first, files after

Database rows for bills are committed before any disk artifacts are written, preventing orphaned files on disk if database transactions roll back.

Writing files first could leave directories on disk without matching `PipelineRunBill` records if the database transaction subsequently fails. When disk artifacts fail to write after the database commit, subsequent stages handle missing files gracefully. Specifically, the `extract_text` stage returns `:skipped_no_pdf`, recording the bill as `"skipped"` with error `"no_pdf_uploaded"` and resetting consecutive failure streaks instead of crashing the run.

## Operator visibility in the per-bill grid

Skipped bills remain visible in the administrative Bill Creator grid, allowing operators to inspect missing artifacts and trigger targeted backfills.

Because database rows exist for all discovered bills, operators can monitor individual bill progress through pipeline stages in the per-bill grid. When a bill is skipped due to missing PDF attachments, its status is transparently displayed with the `"no_pdf_uploaded"` reason rather than disappearing silently.

## Persist protects the guarantee at the write itself

The persist method writes metadata.json before downloading PDF attachments, ensuring metadata exists even if network downloads fail.

If network failures interrupt PDF retrieval, the on-disk `metadata.json` preserves the upstream matter attributes and allows backfill stages to resume downloading attachments without repeating full discovery.
