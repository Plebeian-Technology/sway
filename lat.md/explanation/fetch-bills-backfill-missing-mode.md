---
lat:
  mode: explanation
---

# FetchBillsService's backfill_missing mode

`mode: :backfill_missing` downloads the missing PDFs one bill at a time, reading each bill's Legistar id out of its own `metadata.json`.

It never pages the whole bill list and never writes database rows: the `PipelineRunBill` rows already exist, since backfill only runs after a discover run created them. Like discover mode, this path is wired to Baltimore (`Legistar::Client`'s `DEFAULT_CLIENT = "baltimore"`); supporting other jurisdictions is left for later.

## Why the ready-to-download bills are backfilled before the undiscovered ones are repaired

`external_id` on its own is not unique — bills are unique on `(external_id, sway_locale_id)`.

Which bill the walk lands on decides which `Legislation::Paths` folder the downloaded PDF goes into, so `#call_backfill_missing` only keeps the three values the work needs off each bill (never the `Bill` rows themselves: `bills.extracted_text` holds whole bill texts, and a run has on the order of 166 bills to hold at once on one Raspberry Pi).

The cheap, targeted work this mode exists for — downloading a PDF for a bill whose `matter_id` is already known — runs FIRST, before `#repair_missing_metadata` asks Legistar for the undiscovered bills by name. In this order, a bill that cannot be repaired never costs the bills that only needed a PDF.

## Why repair_missing_metadata asks Legistar instead of reading a file

`#repair_missing_metadata` is chosen for a bill precisely BECAUSE its `metadata.json` is missing — it exists for a stage nobody ticked, added because that artifact is absent.

A version that read the file it exists to create would be self-defeating, so it asks Legistar directly instead.

## Why refuse_when_nothing_was_produced sometimes only warns

`#refuse_when_nothing_was_produced` is a no-op once every undiscovered bill got repaired.

When some are left unrepaired, it only warns — rather than failing the whole run — as long as either some ready bills succeeded, or only some (not all) of the undiscovered bills stayed unrepaired: those bills end the run with no PDF and later stages skip them, but the rest of the run's progress is real.

It raises `BillProcessingError` only when the stage repaired nothing at all: refusing costs the WHOLE run (a run-level stage's error becomes a `StageError`, with no per-bill budget), so one upstream bill being dropped must never discard the repairs that worked. Refusing only in the all-nothing case is also what keeps the stage from being recorded as succeeded, so a resumed run comes back for it.

## Why the write-failure rescue is kept apart from the network rescue

`#call_backfill_missing` rescues `SystemCallError`/`IOError` in a clause separate from its `Faraday::Error`/`Legistar::Client::Error` rescue, so the raised message says which half broke.

Without the separate rescue, a full disk reached the operator as a bare `Errno`.

## Why a bad Legistar response leaves the bill unrepaired rather than raising

`#repair_missing_metadata` rescues `Legistar::Client::HttpError` and `Legistar::Client::ParseError` around its own Legistar call.

`#repair_missing_metadata` rescues `Legistar::Client::HttpError` and `Legistar::Client::ParseError` around its own Legistar call: an error status, or a body that is not JSON, leaves that one bill unrepaired rather than ending the run — the same answer `#fetch_all_matters` gives for the same two error classes.

## Why repair_missing_metadata reads the file back through the caller's locale

`#repair_missing_metadata` asks Legistar for one bill by its file number (`MatterFile`) and writes its `metadata.json` through `#persist`, which always files under this service's own jurisdiction (Baltimore).

The method then confirms success by reading the file back through `Legislation::BillMetadata.matter_id(external_id, sway_locale: locale_name)` — the CALLER's locale, not a hardcoded one — because for any other jurisdiction the file lands where this mode will not look, which is no repair at all. See [[docs/explanation/legistar-response-row-filtering.md|Legistar response row filtering]] for why the returned rows are filtered before `#build_metadata` reads them, the same guard `#fetch_all_matters` uses.

## Why backfill_one re-cleans both halves of the artifact path

`#backfill_one` takes the external_id and locale name off the RESOLVED bill in the caller's walk, not off the `PipelineRunBill` row directly.

`#backfill_one` takes the external_id and locale name off the RESOLVED bill in the caller's walk, not off the `PipelineRunBill` row directly — `PipelineRunBill` carries only `bill_external_id`, which names no single bill on its own, which is what let two jurisdictions share one folder before path segments carried the locale too (see [[docs/explanation/legislation-path-segment-safety.md|Legislation path segment safety]]). `Legislation::Paths` cleans both the external_id and the filename halves of the download path, so neither `FileUtils.mkdir_p` nor `#download_pdf`'s `File.binwrite` can reach outside the artifact root.

## Why bill_id_list caps its output

`#bill_id_list` truncates the pairs it is given to a small number and adds an "and N more" tail.

`RunLegislationPipelineJob#run_run_level_stage` truncates the whole error message at 500 characters, and a run with many undiscovered bills would push the reason for failure off the end before truncation ever gets there.
