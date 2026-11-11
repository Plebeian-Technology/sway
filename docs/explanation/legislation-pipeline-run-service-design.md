---
mode: explanation
summary: "Explains LegislationPipelineRunService's constructor defaults, why resume/restart create a new run row instead of mutating the old one, and why origin must agree between the row and the job."
status: agent-extracted
related: [docs/explanation/resume-stage-history-walk.md, docs/reference/legislation-pipeline-concurrency-layers.md]
---
<!-- vale Vale.Spelling = NO -->

# LegislationPipelineRunService design notes

`LegislationPipelineRunService` starts, resumes, and restarts legislation
pipeline runs: it saves a `LegislationPipelineRun` row and queues the
background job that actually runs the pipeline.

## Why ResumeNotAllowed is raised before anything is created

`#resume` checks that the run being resumed really did fail AND covered a
single bill BEFORE creating anything. Without this check, an invalid resume
would create a queued row, start the job, and only fall over further down
the line, leaving the operator staring at two failed runs.
`BillsController#resume_pipeline_run` catches this and shows the reason as
a flash message.

Whether a run counts as single-bill is worked out from `bill_id`: aimed at
one specific bill means `'single'`, otherwise `'all_bills'`.

## Why `stages:` and `bill:` are optional constructor arguments

`stages:` is optional so that callers using `#resume` or `#restart` — which
take everything from the run they are repeating — can build this service
with no arguments at all. `#run!` still refuses to go ahead when no stages
were given.

`bill:` is how a caller scopes a run to one bill. A caller holding only a
`bill_id` (the picker form payload, for example) should look the `Bill` up
itself.

## download_missing_assets replaced refresh, with nothing left behind

There used to be a `refresh:` argument. `download_missing_assets:` replaces
it outright, with nothing left behind that still answers to the old name.
The `refresh` column itself is still in the database for now, but no code
reads it. When the caller passes nothing to `#initialize`, the service
falls back to `true`, matching the database column's default.

`#run!` only writes `download_missing_assets`. New rows keep whatever the
database default (`true`) puts in the older `refresh` column; no code reads
that column any more, though `to_builder` still reports both exactly as
stored.

## skip_enqueue: lets the controller own the enqueue

`skip_enqueue:` lets `BillsController` queue `RunLegislationPipelineJob`
itself once the row exists. When it is false (the default), `#run!` queues
the job, which is what every other caller relies on.

## Resume copies download_missing_assets; restart can override it

A resume copies `download_missing_assets` straight from the run it repeats
— there is no way for an operator to override it in `#resume`. `#restart`
is different: its `download_missing_assets:` argument defaults to `nil` so
the service can tell "the operator said nothing" apart from "the operator
deliberately said false". When it is `nil`, the value is copied from the
run being restarted; `#resume` has no such argument at all.

Unlike `#resume`, `#restart` does not care what state the earlier run ended
in — restart has no preconditions.

## Why origin: is passed explicitly rather than left to the job's default

Both `#resume` and `#restart` pass `origin:` to
`RunLegislationPipelineJob.perform_later` explicitly, rather than leaving it
to the job's default.

For `#resume`: the job asks the origin whether this is a resume, and only a
resume skips the stages an earlier run already finished (see
[Why succeeded_stage_names_before walks the whole resume chain](resume-stage-history-walk.md)
for the read side of this same agreement). Left to the default, the job
would read "fresh", re-run every stage from the top, and buy the summary
call a second time on a run whose whole point is not to. The row already
says `origin: "resume"`; the two have to agree.

For `#restart`: a restart runs every stage on purpose, so the default would
not change what happens today — but it would make the run's own record and
the job's idea of it disagree, and the next reader would have no way to
tell which is right.

## Why resume and restart create a new run row instead of mutating the old one

Both point back at the original via `parent_run_id` rather than mutating the
original row, so the resume/restart history stays auditable. See
[Why succeeded_stage_names_before walks the whole resume chain](resume-stage-history-walk.md)
for how that chain gets walked back.

## parent_run_id is a string, not the remote_run_id UUID

`LegislationPipelineRun#parent_run_id` is filled in from `parent_run.id.to_s`
(see `LegislationPipelineRunService#resume` / `#restart`, and the column
type on `LegislationPipelineRun`) — it is the parent row's own primary key,
not its `remote_run_id` UUID. Looking a resumed or restarted child up by the
parent's `remote_run_id` finds nothing.

## The removed .concurrency_blocked? method

There used to be a `.concurrency_blocked?` method here. It guarded against a
conflict reported by an external pipeline service that no longer exists. The
controller now checks inline with `active_any.lock("").first`, which is the
real gate: it covers both single-bill and whole-locale runs, and it takes
SQLite's write lock in the same breath as the INSERT that follows. Solid
Queue's `limits_concurrency to: 1` on `RunLegislationPipelineJob` (see
[Legislation pipeline concurrency layers](../reference/legislation-pipeline-concurrency-layers.md))
gives the strict one-run-at-a-time guarantee the old method was reaching
for. See `bills_controller.rb#run_pipeline`.

## Why validate_stages_for! is split out of validate_stages!

Split out of `#validate_stages!` so `#resume` and `#restart` — which get
their stages from the run being repeated rather than from `@stages` — check
against the same list of allowed stages.
