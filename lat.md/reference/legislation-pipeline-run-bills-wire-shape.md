---
lat:
  mode: reference
---

# LegislationPipelineRun.to_builder: pipeline_run_bills

`pipeline_run_bills` in the Jbuilder payload carries the data the per-bill grid needs for its first paint.

- It is built only for all-bills runs (`bill_id` blank). A single-bill run renders no grid, so the field is `nil` and the key comes out as JSON `null` — Jbuilder emits a `nil` value as-is unless `ignore_nil` is switched on, and this app never switches it on.

- The row's `started_at` and `finished_at` are covered by `docs/reference/legislation-pipeline-run-stage-timing-wire-shape.md` under `pipeline-run-bills-timing`, alongside the other three timing pairs they have to read the same as.

## Avoiding N+1 queries

Titles are resolved with one batched `Bill.where(...).pluck(...)` lookup (`Legislation::PipelineBillLookup.title_map`) rather than one `Bill.find` per row, so Bullet (the N+1 query detector) stays green.

- The lookup uses the already-loaded collection (`pipeline_run_bills.to_a`) rather than calling `.pluck` again, because `.pluck` issues a fresh SELECT even when the association is already eager-loaded — and the eager-load set up by `LegislationPipelineRunSourcing` would otherwise be defeated.

## Why the association and the batch iterator both pin a stable order

`LegislationPipelineRun#pipeline_run_bills` is declared with `order(:sort_order)` so the serializer and the per-bill grid always show bills in the same stable order, no matter what order the rows were inserted in.

- `#each_pipeline_run_bill` exists because `find_each` drops the association's `ORDER BY` and walks by id instead, so bills would be processed in the order rows were inserted, not the order the grid shows. `find_each` also warns once per call about the dropped order — before any batching starts, so once per run. Naming the same columns as the cursor (`cursor: [:sort_order, :id]`) restores the order and leaves nothing to warn about. `id` breaks ties: `sort_order` defaults to `0`, and a cursor that repeats can skip or repeat rows between batches.
