---
mode: explanation
summary: "Why PipelineRunsController lost its #show route and became index-only, and how the destructive member/collection actions stay unaffected."
status: agent-extracted
related: [docs/reference/pipeline-runs-controller-actions.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `pipeline_runs` is an index-only admin surface

The admin-gated `PipelineRuns` surface: `GET /pipeline_runs` is read-only;
the destructive actions are `POST /pipeline_runs/:id/force_fail` and
`DELETE /pipeline_runs/orphans`, the second gated server-side on three
per-row checks (no Solid Queue job, age, status). A single-row twin of the
orphan delete existed until it was removed, with no caller on any surface.

`:show` was removed — the Show Inertia page was never built
(only `Index.tsx` exists), so `GET /pipeline_runs/:id` rendered a blank
screen. Index is the read-only surface; the detail page is deferred. The
destructive member/collection actions are unaffected by the `:show`
removal — they're declared explicitly in `config/routes.rb`, not via the
REST `only:` list.

`app/frontend/pages/admin/PipelineRuns/Index.tsx` shows a run's id as plain
text in its table, rather than a `Link` — the detail page
(`admin/PipelineRuns/Show`) was never built and its route was removed.
Re-add a `Link` there when that detail page is built.

## Why `#index` precomputes bill counts

`RunSummarySerializer` builds one small summary row per pipeline run rather
than dumping every database column: each row leaves out database plumbing
(foreign keys and serialized columns), precomputes `bills_total` /
`bills_succeeded` / `bills_failed` so the React side does not have to walk
associations, and includes `failing_stage` so a failed run shows where it
broke at a glance.

Bills and stages are loaded for the whole list in one query each, instead
of one query per run — callers pass in a query that is already sorted and
limited.

### Why a run's `kind` reads off `bill_id`, not `bill_external_id`

A run is `"single"` when it points at one bill, `"all_bills"` when it does
not. The `bill_id` column decides that; `bill_external_id` is only the
human-readable label.

## Why `#force_fail` redirects back to where the operator was

When the Bill Creator page force-fails a global run, `#force_fail` redirects
back there so the new activity-log entry shows up where the operator was
working. This is the same `back_to` handling `#destroy_orphans` uses.

## Why `#force_fail` sets `error_message` before the state transition

`#force_fail` sets `error_message` BEFORE the state transition, so the
failed row names its cause and a stale message from the pipeline itself
doesn't survive the force-fail. This matches how `sweep_stale_pipeline_runs`
records its own cause.
