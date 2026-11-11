---
lat:
  mode: explanation
---

# Why RunLegislationPipelineJob pre-seeds pipeline_run_bills

`RunLegislationPipelineJob#perform` seeds `pipeline_run_bills` rows up front, before the stage loop, in two situations that `FetchBillsService#seed_ar_rows` (Legistar discovery) does not cover on its own.

## Single-bill runs

For single-bill runs, `perform` seeds the `pipeline_run_bills` row up front from `run.bill_id`.

Before this, the only code that seeded rows was `FetchBillsService#seed_ar_rows`, which runs only when `fetch-bills` is one of the stages to run. An operator who picked a single bill, unchecked `fetch-bills`, and ran with "download missing assets" off (so nothing pulled `fetch-bills` back in) was guaranteed to fail: `pipeline_run_bills` stayed empty, the bill-level loop body never ran, the "did anything succeed" count was zero, and a `StageError` fired. Restart reused the same broken stage list and hit the same wall every time.

`find_or_create_by!` makes this safe to run repeatedly — resume, restart, and fresh single-bill runs all pass through this helper (see `RunLegislationPipelineJob#pre_seed_single_bill_pipeline_run_bill!`). For all-bills runs (`run.bill_id == nil`) it is a no-op; `fetch-bills`'s `seed_ar_rows` still handles Legistar discovery for those.

## All-bills runs, from disk

This is the all-bills version of the single-bill pre-seed above.

Sway's `legislation/bills/` directory is mounted from the host machine, while the SQLite database lives in the `sway_storage` Docker volume. Destroying that volume wipes every `Bill` and `PipelineRunBill` row, but the `metadata.json` files on disk survive.

Without this guard, an all-bills run without `fetch-bills` checked would seed zero rows and trip every bill-level stage's `stage_succeeded_count.zero?` guard with the misleading "all bills failed in stage extract_text" — despite a full disk cache. `RunLegislationPipelineJob` therefore rebuilds the rows from disk (see `#hydrate_pipeline_run_bills_from_disk!`), letting the pipeline run its cached stages without network access.

This rebuild is skipped when the operator explicitly checked `fetch-bills` — a fresh discover will seed the rows instead.

## Why the all-bills-runs spec swallows the StageError that follows

The spec for the all-bills, `bill_id: nil` no-op case fakes `FetchBillsService` to return no bills, then calls `#perform` inside a bare `rescue; nil; end`.

The job will most likely raise `StageError` afterward, because the faked `fetch-bills` produced zero bills — that is the ordinary "all bills failed" outcome and has nothing to do with the pre-seed helper under test. The example swallows that expected failure and asserts only what the pre-seed helper is responsible for: that it did not invent a `pipeline_run_bills` row when `run.bill_id` is nil.
