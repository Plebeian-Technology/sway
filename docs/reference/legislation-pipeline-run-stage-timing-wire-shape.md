---
mode: reference
summary: "The wire shape of pipeline run timing: the run-level pair, the pipeline_run_stages rows and the pipeline_run_bills rows in LegislationPipelineRun#to_builder, and the recent_pipeline_runs row served for the run-selector dropdown."
status: agent-extracted
related: [docs/reference/legislation-pipeline-run-bills-wire-shape.md]
---
<!-- vale Vale.Spelling = NO -->

# Pipeline run timing wire shape

Four pairs carry pipeline run timing to the admin surfaces. Three are inside
`LegislationPipelineRun#to_builder` — the run-level pair, the stage rows and
the per-bill rows — and the fourth is the compact row list the run selector
reads. All four state the instant in UTC at second precision.

One representation across all four is a requirement rather than a tidiness
preference. `PipelineTerminalAlerts` feeds the run-level `completed_at` and a
stage row's `finished_at` to the same `exactTime()` helper in a single render,
and both `RowCells` and the pipeline-runs index print a `started_at` **raw**
into a tooltip. A raw `ActiveSupport::TimeWithZone` serializes at millisecond
precision, so a mixed payload puts `2026-08-27T20:19:11.123Z` on one row beside
`2026-08-27T20:19:11Z` on the next.

## run-level-timing

The run's own `started_at` and `completed_at` are emitted as `&.utc&.iso8601`
strings, or null. `started_at` is null until the run leaves `queued`;
`completed_at` is null until it reaches a terminal status, and is then set once
— resume and restart create a new record rather than re-terminating this one.

## pipeline-run-stage-timing

Each `pipeline_run_stages` row in `LegislationPipelineRun#to_builder` carries
exactly six keys:

| Key | Type | Meaning when null |
|---|---|---|
| `stage_name` | string | never null |
| `status` | string | never null |
| `position` | integer | never null |
| `output_summary` | string or null | the stage recorded no summary |
| `started_at` | `&.utc&.iso8601` string or null | the stage has not begun |
| `finished_at` | `&.utc&.iso8601` string or null | the stage has begun but not ended |

Both timestamps carry the same UTC second-precision representation as the
recent-runs row below, for the reason given there.

A run that failed before any stage began serializes an empty stage list rather
than a row with invented times.

## pipeline-run-bills-timing

Each `pipeline_run_bills` row carries `started_at` and `finished_at` in the
same `&.utc&.iso8601` form. Both are null for a row that has not begun, and
`finished_at` alone is null for a row that has begun but not ended. The rest of
the row's key set is documented in
`docs/reference/legislation-pipeline-run-bills-wire-shape.md`.

## recent-runs-row

`LegislationPipelineRunSourcing#recent_pipeline_runs_summary` serves the
run-selector dropdown a newest-first list capped at
`RECENT_PIPELINE_RUNS_LIMIT`. Each row carries exactly six keys: `id`,
`status`, `kind`, `bill_external_id`, `created_at`, `completed_at`.

`created_at` and `completed_at` are emitted as `&.utc&.iso8601` strings,
matching `PipelineRuns::RunSummarySerializer`. Both hashes describe the same
`LegislationPipelineRun` fields and both reach the same frontend `Date`
parsing, so they state the same instant in the same representation rather than
one emitting a raw `ActiveSupport::TimeWithZone` at local offset with
millisecond precision and the other a UTC second-precision string.

`completed_at` is set once, when the run first reaches a terminal status, and
is null for a running run. It is correct per run rather than per attempt
because resume and restart create a new record rather than re-terminating the
existing one.

This hash is not yet an alba resource. New prop serialization is expected to go
through one, and extracting a `RecentPipelineRunResource` with an exact key-set
request spec is the intended end state, as part of the wider migration;
the key set is pinned meanwhile by the `recent_pipeline_runs` example in
`spec/requests/partial_reload_contracts_spec.rb`.
