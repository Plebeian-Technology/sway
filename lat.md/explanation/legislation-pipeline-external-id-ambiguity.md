---
lat:
  mode: explanation
---

# Why external_id needs a sway_locale pair to be unambiguous

`Bill#external_id` is not unique on its own — a `Bill` is unique on `(external_id, sway_locale_id)` together (see [[docs/explanation/legislation-path-segment-safety.md|legislation-path-segment-safety.md]]). Two callers that key data on `external_id` alone learned this the hard way.

## Pipeline::ArtifactPresence.batch_for's disk sweeps

`batch_for` preloads `:sway_locale` and builds a `Set` of `(sway_locale, external_id)` keys to answer "does this bill have this artifact?" without scanning unrelated locales.

For small batches (`<= 10` candidate keys), `batch_for` checks target bill PDF globs and hearing files directly; for larger batches, it scopes its PDF and hearing directory globs to the locales present in the batch. Both paths collect a `(sway_locale, external_id)` pair, never the `external_id` alone. Reading the id alone was wrong twice over: the glob was one directory too shallow (it matched nothing once artifacts gained a `sway_locale` segment); fixing only that would have restored a worse bug — bare ids would let Baltimore's `25-0064` PDF answer for Maryland's `25-0064`, skipping a stage that never ran for it. `Pipeline::ArtifactPresence.present?` builds one exact path per bill and was always right; the batched sweep was the other reader, and only it needed the fix.

Building each bill's own lookup key uses the same coerced form `#present?` builds its path from, since the disk sweeps collect **basenames**. Otherwise a legacy padded id would report "present" in one code path and "absent" in the other.

## The ambiguous-id set in batch_for

An `external_id` does not identify a bill on its own, but `batch_for`'s result map is keyed on the id alone — two locales sharing an id used to mean the second silently overwrote the first's answer.

The fix: a repeated id is dropped from the map rather than guessed at. That reads downstream as "no artifacts known" for that bill, which causes a stage to re-run rather than being skipped on another jurisdiction's evidence — the safer of the two wrong answers.

## LegislationPipelineRun.to_builder's title lookup

The same problem shows up in `#to_builder`'s `pipeline_run_bills` title lookup (see legislation-pipeline-run-bills-wire-shape.md).

A plain `.pluck.to_h` would let whichever jurisdiction's row came last win, so a Baltimore grid row could show a federal bill's title. `Legislation::PipelineBillLookup.title_map` stays a single query but leaves an ambiguous id out of the map, so its row shows no title rather than a wrong one.

## Legislation::PipelineBillLookup: the shared implementation

`Legislation::PipelineBillLookup` is the one place the legislation pipeline turns a `PipelineRunBill`'s `bill_external_id` back into a `Bill`.

`PipelineRunBill` stores only `bill_external_id`, with no foreign key, and four call sites used to look it up with a plain `Bill.find_by` — an `external_id` alone is not enough to identify a bill, for the same reason covered above: the unique index on `bills` covers `(external_id, sway_locale_id)` together, and a shared `external_id` let a lookup return whichever row came first.

### Why an ambiguous id refuses instead of picking one

Sway covers three jurisdictions, and nothing stops one `external_id` turning up twice — a Baltimore id colliding with a state one is plausible.

There is no right one to choose, because `Legislation::Paths` names EVERY file on disk after the `external_id` alone: two bills sharing one also share their metadata, hearings JSON, text, and attachments. The pipeline cannot serve either of them correctly, so `.find` serves neither and says so via `warn_ambiguous`.

Where the caller already knows the locale, `.find` narrows by it, settling the collision properly instead of refusing — a run aimed at a single bill knows its locale from `run.bill`. A run over all bills has no locale to offer, since `legislation_pipeline_runs` has no `sway_locale_id` column, so it gets the refusal.

`.title_map` is the display side of the same bug: the admin per-bill grid used to show whichever jurisdiction's title `pluck.to_h` happened to write last. It runs one query and leaves an ambiguous `external_id` out of the result map, rather than guessing at it.

### Why warn_ambiguous is deliberately public

`Legislation::PipelineBillLookup.warn_ambiguous` is public rather than a private helper reached through `send`.

Every place that keys anything on an `external_id` alone faces the same collision and must say the same thing — `Pipeline::ArtifactPresence.batch_for` is the second such place. A private helper reached through `send` is not a shared decision, it is a copy with extra steps.
