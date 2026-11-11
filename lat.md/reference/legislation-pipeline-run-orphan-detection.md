---
lat:
  mode: reference
---

# LegislationPipelineRun orphan detection

An orphan is a row that has sat in `queued` or `running` status for over 4 hours (`ORPHAN_AGE_THRESHOLD`) with no live Solid Queue job working on it.

- The worker died before finishing, so the row will never make progress on its own. Operators can hard-delete orphans through the bulk endpoint on `PipelineRunsController`.

## How this differs from the stale-run sweep

The 4-hour age gate is what separates orphan detection from `sweep_stale_pipeline_runs` (`BillsController`).

- That sweep marks any `queued`/`running` row failed right now, with no age check. Orphan detection waits 4 hours so a run that is genuinely progressing, just between worker heartbeats, is not pruned by mistake.

## The three checks

`#orphan?` returns `true` only when a run passes all three checks:

1. `status` is `queued` or `running`.
2. the row is older than the 4-hour threshold.
3. no live Solid Queue job references this run's id.

## The Solid Queue job lookup

`.solid_queue_job_exists_for?` is the shared query behind check 3.

- Solid Queue stores each job's `active_job.serialize` output in the `arguments` column as a JSON blob; `$.arguments[0]` is the `run_id` passed to `RunLegislationPipelineJob#perform`. Extracting that exact field avoids the false positives a `LIKE '%<run_id>%'` substring match would produce.

- It is a class method so both `#orphan?` and `#abandoned?` share this one query. `PipelineRunsController`'s private `#solid_queue_job_exists_for?` is a same-named wrapper around it with no production caller left, kept only because `spec/requests/pipeline_runs_solid_queue_anchor_spec.rb` pins that wrapper's name and exercises it directly against a real Solid Queue database.

- The lookup fails closed: any exception inside it returns `true` ("a job exists"), so callers refuse to treat the row as deletable. The 4-hour age gate and status gate still apply, so once the underlying Solid Queue issue is fixed the row becomes deletable again.

## Abandoned runs: a second, separate check

`#abandoned?` is a different question from `#orphan?`, checked on `updated_at` rather than `created_at`: a run that finished five stages and stopped in the sixth is old but was working recently.

- Its own threshold, `ABANDONED_AFTER` (also 4 hours), is `RunLegislationPipelineJob`'s own lock duration, not `ORPHAN_AGE_THRESHOLD`.

- `abandoned_candidates` is not merged with `orphan_age_candidates`: that scope covers `queued` and `running` only, and callers delete the row. `abandoned_candidates` covers every `PHASE_52_NON_TERMINAL_STATES` status, and callers close it instead. The run that motivated this scope had sat open 477 hours in `summarizing`.

- Silence alone proves nothing here either — a healthy run leaves its row untouched for an hour inside one stage. `#abandoned?` follows the same order as `#orphan?`: the two cheap checks (status, age) run first, and the live-job lookup — the judgement, not the timestamp it rests on — runs last, since a screen cannot reach the queue database and the lookup is the only one of the three that costs a query.
