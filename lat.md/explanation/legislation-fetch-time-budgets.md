---
lat:
  mode: explanation
---

# Legislation fetch time budgets

Why `FetchBillsService` gives its two network loops a start-by deadline, and why a named Legistar lookup is cheaper than re-running discovery.

## The two unbounded loops

`FetchBillsService#call_discover` (Baltimore's bill-fetch stage) has two loops that reach the network once per bill:

- **Discovery** — one Attachments request per bill, to find each bill's PDF.
- **Download** — up to four requests per bill (through
  `Legistar::AttachmentFetch`) to pull the PDF bytes down.

Neither loop originally had a deadline. `FetchHearingsService` reached the same conclusion for its own loops first; `DISCOVERY_BUDGET_SECONDS` and `DOWNLOAD_BUDGET_SECONDS` in `FetchBillsService` are the sibling budgets for the loops that were left unbounded there.

## The arithmetic behind the numbers

`Sway::FaradayStack.legistar` retries each request up to 4 times, at a 30 second timeout per try, with 0.5s, 1s, and 2s of backoff between tries.

That means **one blackholed request costs about 123.5 seconds** — because the request times out rather than being refused outright, which is the ordinary way a CDN fails.

Neither loop raises when that happens: the discovery loop records "no PDF" for that bill and carries on; the download loop swallows the error and carries on. With about 166 bills in a typical Baltimore run, that means:

| Loop | Requests | Worst case per bill | Total worst case |
|---|---|---|---|
| Discovery | 1 Attachments request per bill | ~123.5s | ~5.7 hours |
| Download | up to 4 requests per bill via `Legistar::AttachmentFetch` | ~494s | ~22.8 hours |

Nothing above these loops has a watchdog. Without a budget, a run in this state simply never finishes, and the operator sees a pipeline stuck "running" with no error to read.

## Why stopping early is safe

Nothing is lost when a budget is hit:

- A bill the discovery loop never reaches has no `metadata.json`, so the
  next run discovers it fresh.
- A bill the download loop never reaches already has its database row, and
  the backfill mode (`mode: :backfill_missing`) exists precisely to fetch a
  PDF for a bill that has none.

Stopping early costs a second run. Not stopping costs the whole day.

## Deadlines are start-by, not wall-clock ceilings

Like the `FetchHearingsService` pair, both budgets are checked BEFORE each bill starts, not mid-request. That means each loop can overshoot its budget by up to one bill's worst case — it is a start-by deadline, not a hard ceiling.

## Why repair_missing_metadata asks by name instead of re-running discovery

When backfill mode (`FetchBillsService#call_backfill_missing`) finds a bill with no `metadata.json` on disk.

When backfill mode (`FetchBillsService#call_backfill_missing`) finds a bill with no `metadata.json` on disk, `#repair_missing_metadata` asks Legistar for that one bill by its file number (`MatterFile`), rather than re-running full discovery.

Re-running discovery is not a cheap fallback here: it costs about 45 minutes of budget (see the arithmetic above), and its `seed_ar_rows` step would grow the run past the bills the operator picked for this backfill — which would carry the paid summarize stage along with it, running (and billing for) work the operator never asked for.

The named lookup is also careful about how it builds its filter: `Legislation::Paths::EXTERNAL_ID_PATTERN` admits no quote character, so the value it validates cannot break out of the OData filter string Legistar receives; `FetchBillsService#fetch_all_matters` builds its own filter the same way.

Asking by name casts a slightly wider net than discovery does: it can also return a `Resolution`, or a bill introduced outside the year window `#default_years` covers — both of which `#fetch_all_matters` filters out during ordinary discovery.

## Why the download loop keeps writing metadata.json after its budget is spent

Once `#persist_within_budget` detects its deadline has passed, the loop does NOT stop.

Every remaining bill still gets its `metadata.json` written — a local write costing nothing — and only the network half (`download: false`) is skipped. That is what leaves the skipped bills in the exact state `mode: :backfill_missing` exists to repair: a database row and a `metadata.json`, but no PDF yet.
