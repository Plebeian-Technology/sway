---
lat:
  mode: explanation
---
# Coercing Legistar's MatterIntroDate

`FetchBillsService#coerce_introduction_date` handles Legistar's `MatterIntroDate` field carefully, normalizing strings and timestamps while ensuring malformed values do not terminate run-level pipeline execution.

The method branches on the incoming value's shape to extract an ISO 8601 string or fall back safely:

- **`String`** — parsed with `Time.zone.parse`. That call returns `nil` for a string it merely cannot make sense of, but raises `ArgumentError` for impossible calendar dates (`"99-99-99"`, `"2025-13-45"`). Both cases are caught and routed through `#warn_intro_date`, returning `nil`. This logs an operator warning without raising out of the service or aborting the run-level stage.
- **`Integer`** — treated as seconds since the Unix epoch, via `Time.zone.at`. Values outside what `Time` can represent raise `RangeError` or `ArgumentError`, which are rescued and routed through `#warn_intro_date` as `nil`.
- **`nil`** — passed through quietly. Legistar legitimately omits introduction dates on matters that represent administrative attachments.
- **anything else** (such as unexpected `Hash` or `Array` payloads) — logged through `#warn_intro_date` and coerced to `nil`.

## Why unexpected types warn and fall back instead of raising

An unhandled exception in `FetchBillsService` escapes to `RunLegislationPipelineJob`'s run-level handler, force-failing the entire pipeline run and stopping all other bills from completing subsequent stages.

`FetchBillsService` executes as a run-level stage (`run_run_level_stage`), where no per-bill failure budget exists. Raising `BillProcessingError` on an unexpected date type in a single bill's upstream payload therefore aborts the run for every bill in the batch.

Coercing unexpected values to `nil` with a warning accepts that `LegislationIngestionService#apply_bill_attributes` will substitute the run timestamp (`bill.introduced_date_time_utc ||= Time.current`). While this means an anomalous bill is stamped with its ingestion time rather than its true introduction date, the failure is isolated to that bill: an operator warning is logged in the pipeline activity stream, and remaining bills proceed through text extraction, diff generation, and summarization.
