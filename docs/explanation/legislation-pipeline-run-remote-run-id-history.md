---
mode: explanation
summary: "Explains why remote_run_id on LegislationPipelineRun is generated locally instead of staying blank, and which consumers depended on it having a value."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why LegislationPipelineRun generates its own remote_run_id

`remote_run_id` used to be filled in by a webhook from a separate Python
service that ran the pipeline. That service is gone, and nothing else wrote
the column, so new rows were left blank.

## Two consumers still needed a value

Even after the webhook disappeared, two other parts of the app still keyed
on `remote_run_id`:

- `PipelineActivityLogger#resolve_stream_id` falls back to `"global"` when
  the column is blank, so activity log entries broadcast on the wrong
  channel.
- The frontend hook `usePipelineRunSubscription` bails out when
  `remote_run_id` is falsy (`if (!runId) return;`). `PerBillGrid` then never
  receives partial-reload updates and shows an empty state for the run's
  whole lifetime, even though `pipeline_run_bills` rows exist on the server.

## The fix

`LegislationPipelineRun` now generates a UUID for `remote_run_id` at create
time (`before_validation :assign_remote_run_id, on: :create`). This keeps
the channel-keying contract intact without changing either consumer.

## Why the guard against overwriting stays

`#assign_remote_run_id` only fills the column in when it is blank, rather
than writing it unconditionally. An earlier version of this same guard's
comment cited `LegislationPipelineRunService#sync_from_remote` as the
writer it protects against; no such method exists. It belonged to the
webhook backfill flow that came in with the Python sidecar and was deleted
with it, so nothing writes this column ahead of creation today. The guard
stays anyway because it costs nothing, and a caller may set the value
again later.

## What the list-page row surfaces about it

`PipelineRuns::RunSummarySerializer` sends `remote_run_id` in the row it
builds for the `/pipeline_runs` list page. It is meaningless on its own,
holds no personal data, and only admins see it. The list page subscribes
with it, so rows update themselves while a run is in flight — nobody has
to refresh. A run still waiting in the queue has no id yet, so this can be
nil, and the React side treats that as null.
