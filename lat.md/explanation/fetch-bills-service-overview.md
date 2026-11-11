---
lat:
  mode: explanation
---

# FetchBillsService overview

Explains FetchBillsService's constructor contract, why #call writes database rows as part of a file-fetch stage, its network-failure granularity, and the single-bill scoping filter.

## Why bill_run: stays on the constructor even though this stage never uses it

`FetchBillsService.new` takes `run:`, `bill_run:`, `mode:`, and `faraday_conn:`.

`bill_run` is not used: this stage runs once for the whole pipeline run rather than once per bill, so there is no single per-bill row in scope. It stays on the constructor anyway so every stage can be constructed the same way, with `new(...).call` — `RunLegislationPipelineJob` passes `bill_run: nil` for run-level stages like this one.

`run:` is used for structured logging and as the parent of the `PipelineRunBill` rows created in `#seed_ar_rows`. This stage runs once per pipeline run rather than once per bill, but it is still the only place those per-bill rows get created; every later per-bill stage assumes `run.pipeline_run_bills` is filled in.

## Why call is safe to run twice

Safe to run twice: with the same `@run` it finds the `Bill` and `PipelineRunBill` rows that already exist and creates no duplicates.

The database enforces that with unique indexes on `bills(external_id, sway_locale_id)` and on `pipeline_run_bills(legislation_pipeline_run_id, bill_external_id)`.

## Why call writes database rows as part of what looks like a file-fetch stage

Writing the `Bill` and `PipelineRunBill` rows in `#call_discover` is part of the deal, not an add-on.

Writing the `Bill` and `PipelineRunBill` rows in `#call_discover` is part of the deal, not an add-on: every per-bill stage (`extract_text`, `parse_sections`, `fetch_hearings`, `generate_diffs`) walks `run.pipeline_run_bills`, and the orchestrator fails the run when a stage succeeds for zero bills — so if this stage only wrote files, every stage after it would fail with nothing to walk.

Bill writes go through `LegislationIngestionService#upsert_bill_payload` so the one canonical path — locale and legislator lookup, defaults for the fields `Bill` requires, and safety against two processes inserting the same bill at the same moment — gets reused, instead of a second copy of those defaults living here. `FetchBillsService#bill_data_from_metadata` translates this service's Legistar-shaped metadata into the string-keyed payload `#upsert_bill_payload` wants: Legistar's `MatterTitle` becomes `title`, `MatterIntroDate` becomes `introduced_date_time_utc`. Columns Legistar does not give us (chamber, status, summary, link, category) are left for `LegislationIngestionService#apply_bill_attributes` to default — the same path `SeedBill` and webhook ingestion already use. `sway_locale_external_id` is set to the already-resolved Baltimore locale's name, so `#resolve_sway_locale` picks the very locale this service already looked up — belt and braces, and one source of truth for that locale-name string.

`#seed_ar_rows` wraps its whole loop (one `upsert_bill_payload` call plus one `PipelineRunBill.find_or_create_by!` per metadata) in a single `ActiveRecord::Base.transaction`. A failure partway through — a `NameError` from a typo, say, or a unique-index collision the upsert cannot recover from — leaves `@run` with ZERO per-bill rows rather than a half-built set the orchestrator would then walk.

See [[docs/explanation/bill-artifact-write-ordering.md|Bill artifact write ordering]] for why those database rows are written before any file touches disk, and why `#persist` still keeps working when only the filesystem half fails.

## Why only a fetch_all_matters failure is fatal to the whole run

`#call_discover` rescues `Faraday::Error` and `Legistar::Client::Error` around its whole body, but by the time that rescue can fire, almost every network call inside it has already handled its own failure locally.

`#call_discover` rescues `Faraday::Error` and `Legistar::Client::Error` around its whole body, but by the time that rescue can fire, almost every network call inside it has already handled its own failure locally: `#fetch_attachments_safely` (used during discovery) and `#persist`'s own rescue both catch a single bill's network problem and let discovery carry on for the rest. The only network failure that still reaches the outer rescue is one from paging through the bill list itself (`#fetch_all_matters`) — meaning the run cannot even find out which bills exist. That one stays fatal, and rightly so: there is nothing to write. `#fetch_all_matters` raises `Legistar::Client::Error` (which wraps the underlying `Faraday::Error`) for a network failure, while the raw `#download_pdf` path still raises `Faraday::Error` directly, so the rescue clause catches both.

## Why attachment-fetch failures degrade instead of aborting discovery

`#fetch_attachments_safely` is the discover path's safety net around the raw `#fetch_attachments`.

Only `#build_metadata` calls it, from the per-matter loop in `#call_discover`, so when one matter's Attachments endpoint drops the connection — after `Sway::FaradayStack`'s retries are used up — that single bill degrades to "no PDF" and can be backfilled later, instead of raising a `BillProcessingError` that aborts discovery of every other bill in the run. `mode: :backfill_missing` keeps calling the raw `#fetch_attachments` and keeps its own fail-hard behavior on purpose: a backfill run exists only to fetch the PDFs an operator picked, so there is no larger batch of bills its own network failure could protect.

## Why single-bill runs filter the fetched matter list down to one

`RunLegislationPipelineJob` sets `@run.bill` when an operator clicks "Refresh pipeline for &lt;bill&gt;", or runs the pipeline for a single bill.

`#scope_to_run_bill` filters the fetched metadata list down to that one bill's `external_id` before `#seed_ar_rows` runs. Without this filter, `#call_discover` would create `PipelineRunBill` rows for every Legistar matter, and every later per-bill stage would then walk all of them — which defeats the whole point of refreshing one bill.
