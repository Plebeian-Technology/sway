---
mode: explanation
summary: "Explains the write boundary LegislationIngestionService enforces, why each bill upsert runs in its own transaction, and how it resolves a bill's locale and fallback legislator."
status: agent-extracted
related: [docs/reference/legislation-pipeline-concurrency-layers.md, docs/explanation/bill-json-payload-design.md]
---
<!-- vale Vale.Spelling = NO -->

# LegislationIngestionService design notes

`LegislationIngestionService#upsert_bill_payload` is the one place the
legislation pipeline writes bill rows into the tables Rails owns. `FetchBillsService`
calls it once per bill as it finds them; each call wraps its own
writes in a transaction, so the same bill arriving twice does no harm.

## The write boundary: what this service is and is not allowed to touch

Rails performs every write here; the pipeline only hands over structured
JSON. `ALLOWED_BILL_COLUMNS` and `ALLOWED_PROVISIONING_COLUMNS` name exactly
the columns this service may write. The summary columns (`llm_summary`,
`llm_full_breakdown`, `draft_org_positions`) are deliberately left off both
lists — they belong to `GenerateBillSummaryJob`'s own ingestion path, and
this service must never write them. `apply_bill_attributes` looks up
`legislator_id` and `sway_locale_id` from the payload rather than copying
IDs straight out of it, since those are references to other records that
need resolving, not raw column values.

## Why each bill upserts inside its own transaction

An earlier note here worried that each nested transaction (a SQLite
SAVEPOINT) forces a flush to disk. It does not: with WAL mode (SQLite's
write-ahead log) and the default `synchronous=NORMAL`, the log is flushed on
COMMIT and at checkpoints, not on every SAVEPOINT. If the time `seed_bills`
spends per bill ever grows enough to measure, that is the moment to look
again — file an issue then, sketching a `wrap_in_transaction:` option.

## Why DEFAULT_LOCALE_NAME is a last resort, not the usual answer

The pipeline only covers Baltimore today. Once a second locale joins, the
payload will carry `sway_locale_external_id` and `DEFAULT_LOCALE_NAME`
becomes the fallback rather than the value every bill resolves to.

## Filling in required values the payload may leave out

Pipeline ingestion is only for seeding and backfilling; the admin Bill
Creator is still the proper way to enter a fully filled-in bill.
`apply_bill_attributes` fills in the values a `Bill` insists on but the
payload may omit — the database forbids NULL there and the model checks
they are present. See `app/models/bill.rb` for which fields must be
present.

## Why the locale lookup is memoized per service instance

`SwayLocale#name` is put together from city, region and country rather than
stored in a column, so the database cannot filter on it and the lookup has
to happen in Ruby (the same reason `SwayLocale.resolve_by_computed_name`
exists). `resolve_sway_locale` runs once per bill inside a loop, so the
`@all_locales` memo avoids reloading the whole table on every call.

## Why a bill's fallback legislator must be the locale's Council President

The payload leaves out `legislator_external_id` on purpose for seeded and
backfilled bills. `fallback_legislator` insists that the locale actually has
a Council President on file, rather than quietly crediting a bill's
sponsorship to whichever legislator happens to have been added first.

A legislator's title lives on their current term, not on the legislator row
itself — the old `legislators.title` column is gone — so the lookup joins
to the active term to find it.
