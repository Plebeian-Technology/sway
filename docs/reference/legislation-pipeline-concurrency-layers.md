---
mode: reference
summary: "Documents the three layers that keep concurrent legislation pipeline runs from stepping on each other, from the queue lock down to the database schema."
status: agent-extracted
related: []
---
# Legislation pipeline concurrency layers

<!-- vale Vale.Spelling = NO -->

`RunLegislationPipelineJob` allows strictly one run at a time: a second
enqueue raises so the controller can return HTTP 409 instead of quietly
merging two pipeline runs into one.

Three layers keep concurrent runs from stepping on each other. Don't weaken
any single layer without auditing the others.

## Layer 1: the Solid Queue lock

Solid Queue's `limits_concurrency to: 1` on the `legislation_pipeline_global`
key. Two concurrent enqueues raise instead of merging. The lock holds for
`duration: 4.hours` — see
[Legislation pipeline lock duration](../explanation/legislation-pipeline-lock-duration.md)
for what that window does and does not cover, and why it is 4 hours.

## Layer 2: the database schema

`pipeline_run_bills` has a unique index,
`index_prb_on_run_and_bill_external_id`, on
`(legislation_pipeline_run_id, bill_external_id)`. If Layer 1 ever leaks (the
duration expires mid-run, or Solid Queue restarts), `FetchBillsService#seed_ar_rows`
uses `find_or_create_by!`, which catches the resulting
`ActiveRecord::RecordNotUnique` and refetches — the caller never sees an
error.

## Layer 3: the cross-run Bill upsert

`LegislationIngestionService#upsert_bill` handles two runs upserting the same
`Bill` by reloading on conflict against the `bills(external_id, sway_locale_id)`
index.
