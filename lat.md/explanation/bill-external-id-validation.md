---
lat:
  mode: explanation
---
# Bill external ID validation

External bill identifiers are validated against path-traversal patterns at every intake boundary before becoming filesystem path segments, ensuring single-row anomalies never abort multi-bill pipeline runs.

## Why external IDs require path validation

A bill's external identifier serves as a filesystem directory name across pipeline artifact operations, making strict format validation essential to prevent path traversal.

Without validation, malformed values containing relative path sequences such as `../` could write files outside designated artifact directories. Because external IDs originate from upstream government data or operator edits, every entry point verifies that the value conforms to safe segment rules rather than trusting incoming text.

## Validating external bill identifiers

Persist and backfill operations guard external ID path segments with non-raising helpers, ensuring an unusable ID skips only that bill rather than aborting the pipeline run.

In `FetchBillsService#persist` and `GenericLegislationAdapter#backfill_bill`, checking `Legislation::Paths.external_id_segment` prevents `Legislation::Paths::UnsafeExternalIdError` from escaping to the run-level stage handler in `RunLegislationPipelineJob`. When an external ID fails segment validation, the service logs a warning naming the bill and skips artifact creation for that row, allowing all valid companion bills in the batch to complete ingestion.

## Validation at discovery and disk intake

Intake paths validate candidate external IDs with non-raising helpers, discarding malformed upstream rows before directory paths are constructed.

During discovery, upstream matter identifiers are validated via `Legislation::Paths.external_id_segment`. Invalid rows return nil and are excluded from ingestion batches in `seed_ar_rows`. When reading existing `metadata.json` files from disk in `#read_disk_metadatas`, any row with an invalid segment is logged with an operator warning and skipped, ensuring corrupted files do not interrupt database reconstruction.

## Model format validation and factory fixtures

Database model validation and test factories reinforce path safety rules early in the lifecycle, preventing unsafe external IDs from persisting.

`Bill::EXTERNAL_ID_PATTERN` mirrors `Legislation::Paths::EXTERNAL_ID_PATTERN`, validating records on save when `external_id` changes. Factory definitions parameterize random strings to guarantee generated test data consistently conforms to the expected regex.

## Entry point 1: Legistar's MatterFile field

`FetchBillsService#build_metadata` builds candidate external IDs from Legistar's free-text `MatterFile` field, requiring path segment validation before acceptance.

Validation guards against two failure modes:

- A value padded with spaces would pass a simple presence check, but would fail `BaltimoreLegislatorVoteUpdateService::MATTER_FILE_PATTERN` on every subsequent vote sweep.
- Trimming spaces alone is insufficient because it strips neither `/` nor `..`, leaving path traversal risks intact across filesystem operations.

`Legislation::Paths.external_id_segment` rejects malformed segments at intake. Returning nil allows `#build_metadata` to drop unusable rows alongside skipped matter types without stopping discovery for companion bills.

`MatterFile` can arrive as any JSON scalar or array. `Legislation::Paths` accepts only a `String` or nil to keep wire decoding decoupled. The `.to_s` conversion turns non-string payloads into text that the segment pattern subsequently rejects.

## Entry point 2: operator-edited metadata.json

`FetchBillsService#read_disk_metadatas` rebuilds database records from disk `metadata.json` files that operators may have edited directly, requiring renewed segment checks.

Values read from disk flow to `Bill#external_id`, `PipelineRunBill#bill_external_id`, and `FileUtils.mkdir_p` in `#persist`. `#read_disk_metadatas` passes candidates through `Legislation::Paths.external_id_segment` rather than trusting unverified files on disk.

Rows failing validation are skipped with a warning log, matching error handling for blank identifiers, non-integer matter IDs, or unparseable JSON so that a single corrupted file never aborts database reconstruction for valid bills.

## The bill factory's external_id fixture

The `:bill` factory in `spec/factories/bills.rb` generates `external_id` values using parameterization to prevent unexpected pattern failures.

`external_id` is validated against `Bill::EXTERNAL_ID_PATTERN`. While Faker's English color names currently match the pattern, future word additions could violate format expectations. Calling `.parameterize` enforces `[a-z0-9-]` compliance and insulates test suites from upstream dictionary changes.

## Why the format spec updates a saved bill instead of using build(:bill)

`build(:bill)` is perpetually invalid because the factory's initialization leaves `legislator_id` unpersisted, making unsaved validity assertions meaningless.

Testing format validation against an unsaved instance would pass regardless of the candidate `external_id`. The format specification instead mutates `external_id` on an already persisted bill, isolating the attribute under test and exercising the `if: :external_id_changed?` model callback on a persisted record.

`scheduled_release_date_utc` remains unset in this fixture because multiple bills are instantiated within a single locale, where duplicate scheduled release dates are prohibited.

## Why a stored external_id is stripped rather than rejected

Leading and trailing whitespace around `external_id` is sanitized automatically rather than causing validation rejections.

Legistar's `MatterFile` input is stripped upon intake, and `Legislation::Paths.external_id_segment` strips values when generating directory paths. Normalizing whitespace at the model layer ensures stored records, filesystem segments, and query parameters remain in agreement.

## Related filtering mechanisms

Companion defensive measures protect intake pipelines against malformed responses arriving before external identifier extraction.

[[docs/explanation/legistar-response-row-filtering.md|Filtering malformed API response rows]] documents upstream defense against nil rows encountered during ingestion.

