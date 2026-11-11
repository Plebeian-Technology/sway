---
lat:
  mode: explanation
---

# BillCreatorPipelineStatusBadge unrecognized-status fallback

Used to return null for any status missing from its own hand-copied STAGE_LABELS — now reads the shared stage list and falls back to the raw status.

(`app/frontend/components/admin/creator/__tests__/BillCreatorPipelineStatusBadge.test.tsx`)

## How the status vocabulary is shaped, and why it isn't copied

How an all-bills run can end: 'succeeded' means every bill went through cleanly, 'partial' some failed — both terminal. 'completed' stays so old rows still display.

While in progress, status is the stage name (fetching_bills, etc.) — this badge shows it as "running" plus the stage name, instead of a blank space as before.

The status list and stage labels live once in pipeline-controls/stages.ts — not copied here — so this badge cannot drift from PipelineProgress and RunSelector.

## Why stale and the empty_artifact marker are checked ahead of status

Copied from bill_artifacts.stale when fetch-bills sees the upstream document changed. Stale outranks whatever status says, so the warning is never hidden.

The pipeline marks a stage that finished but wrote nothing with an error_message starting "empty_artifact:" — shown as "Failed — no output" instead of plain failed.

Stale outranks success/running — the warning shows regardless of how the run ended.

The "empty_artifact:" marker gets its own wording, telling the operator the stage ran but produced nothing. Plain "Failed" means the stage crashed.

## Why bill scope uses "Refreshing…" instead of "Running"/"Queued"

Bill scope used to say "Refreshing…" for `queued` too, contradicting the "Queued" text right next to it in LlmSummaryPipelineBusyNotice — now both scopes distinguish the two.

Bill scope keeps its own word for `running` ("Refreshing…") because that names what's happening to THIS bill's data; "Running" doesn't.
