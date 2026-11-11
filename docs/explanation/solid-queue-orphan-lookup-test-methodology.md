---
mode: explanation
summary: "Why pipeline_runs_solid_queue_anchor_spec.rb swaps SolidQueue::Job for a same-connection stand-in table instead of the real second Solid Queue database, and the coverage gap that leaves."
status: agent-extracted
related: [docs/reference/legislation-pipeline-run-orphan-detection.md]
---
<!-- vale Vale.Spelling = NO -->

# Why the Solid Queue anchor spec tests against a stand-in table

`spec/requests/pipeline_runs_solid_queue_anchor_spec.rb` runs the real
`json_extract` SQL behind `PipelineRunsController#solid_queue_job_exists_for?`
against a database, rather than stubbing the method.

## Why a stand-in table, not the real Solid Queue database

The test environment uses a single SQLite database
(`config/database.yml`). In development and production, Solid Queue gets
its own database, but the query under test talks to `SolidQueue::Job`
directly. To run the real `json_extract` SQL without dragging in that
second-database wiring, this spec swaps `SolidQueue::Job` — for this file
only — for a small ActiveRecord model backed by a table it creates on the
main connection. The SQL itself is what's being tested, not which
database it goes to. Cleanup is kept narrow: the spec drops only the
table it created.

## The known gap this leaves

The query is checked for syntax against a table on the main connection.
In production, `SolidQueue::Job` lives in a separate queue database. A
future rewrite of `solid_queue_job_exists_for?` that reached across both
databases — joining `LegislationPipelineRun` into the same query, for
instance — would break in production and still pass here. That gap is
known and accepted.

## Why the method-existence check runs first

Every example calls `controller.send(:solid_queue_job_exists_for?, run)`,
using `.send` to reach a private method, so renaming that method would
produce a separate `NoMethodError` stack trace per example. A single
`before(:all)` assertion that the method still exists replaces all of
those with one clear failure message.

## `spec/jobs/solid_queue_retention_job_spec.rb` uses the same trick

`SolidQueueRetentionJob`'s spec exercises the real delete SQL against real
tables, not fakes, for the same reason and with the same stand-in-table
technique described above: the test environment has one SQLite database,
while dev and production keep `SolidQueue::Job` and
`SolidQueue::FailedExecution` in a separate queue database. To run the
real SQL without that multi-db setup, the spec swaps those two constants
for small throwaway models on the main connection and drops the tables
afterward.

## Why the serialized job arguments are spelled out by hand

`spec/requests/pipeline_runs_solid_queue_anchor_spec.rb`'s
`serialized_active_job_arguments` helper builds the same JSON
`ActiveJob::Core#serialize` writes for
`RunLegislationPipelineJob.perform_later(run_id, origin: "fresh")`,
written out by hand rather than pulled from the gem itself. That way, if
a future ActiveJob version changes the serialized shape, this spec fails
instead of production quietly matching nothing — pulling the shape from
the gem would let the test track any future drift silently, defeating
the point of pinning the shape at all.
