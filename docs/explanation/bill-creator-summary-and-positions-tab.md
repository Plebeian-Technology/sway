---
mode: explanation
summary: "Why BillCreatorSummaryAndPositions listens on a scoped ActionCable subscription plus a mount-driven SummaryGenerationPoller, how isGenerating/hasNoProvisioning are worked out during render, and why the LLM summary key is llm_generated_at."
status: agent-extracted
related: [docs/explanation/summary-tab-pipeline-running-poll-fallback.md]
---
<!-- vale Vale.Spelling = NO -->

# BillCreatorSummaryAndPositions mechanics

## Why SUMMARY_AND_POSITIONS_ONLY_PROPS is a shorter, separate list

What a live update refetches on the Summary & Positions tab.

Shorter list than the Pipeline tab's — this tab only needs what feeds the
LLM summary card and the draft organization positions. `bill` carries the
summary; `organizations` fills the positions list.

`active_legislation_pipeline_run` is on the list so the ActionCable
subscription below can follow it — a run finishing greys out Regenerate
and clears running/failed state with no reload.

It is the TRULY active run, not whatever ?run_id= is pinned in the address
— see legislation_pipeline_run_sourcing.rb and RunConflictBanner for why
the two must stay separate props.

## Why SummaryGenerationPoller takes no props and has no start/stop pair

A tiny component whose only job is to re-ask the server for data on a
timer.

Appears while a one-off summary job is running, there is no provisioning
row yet, or a pipeline run is going on this bill; disappears once none
holds.

No start/stop pair and no effect — whether this component is mounted IS
the on/off switch.

Replaces an earlier `useEffect(() => isGenerating ? start() : stop())` —
effects sync React to the outside world, not toggle something React
already mounts/unmounts for us.

IMPORTANT: takes no props on purpose (`Record<string, never>`): `usePoll`
reads its interval and refetch list only on first render — its
@inertiajs/react dependency array is empty.

If this poller ever needs to be configurable, give it a React `key`
derived from that value so it remounts — a plain re-render will not pick
up new arguments.

## Why this tab holds sections that used to sit on the Pipeline tab

The tab where an editor works on a bill after the pipeline has run.

It holds two sections that used to sit on the Pipeline tab:
BillCreatorLlmSummary (the "out of date" chip, Regenerate, and pasting a
summary in) and BillCreatorOrganizations (the positions panel).

It listens on PipelineRunChannel so the summary section updates itself the
moment the summarize stage finishes, instead of making the operator hop
back to the Pipeline & LLM tab to force a refresh.

A summary generated outside a pipeline run has no run record for that
channel — SummaryGenerationPoller below watches it, appearing only while
its plain GenerateBillSummaryJob is running.

## Why isGenerating and hasNoProvisioning are worked out during render

Worked out during render, no stored state, no effect: a polled reload
lands, generation_status becomes "completed"/"failed", isGenerating turns
false, and the poller unmounts itself.

LlmSummaryEmptyState renders only with no provisioning row — the one
branch neither trigger reaches: isGenerating needs a row, and the
subscription only follows the run active at mount.

Without this, LlmSummaryEmptyState's promptIsStale guard has no way to
learn pipeline status moved underneath a prepared prompt, and could keep
offering copy for a stale bill version.

## Why mounting/unmounting the poller is the only start/stop mechanism

Mounting starts the polling; unmounting stops it via usePoll's own cleanup. Also mounted while there is no provisioning row, so
LlmSummaryEmptyState's staleness guard sees fresh status.

## Why BillCreatorLlmSummary is keyed by llm_generated_at, not by anything else

The React key is when the summary was generated, so the component rebuilds
whenever a paste-back or regenerate saves a new one. No summary yet uses
key "none".

This key is NOT how the two text boxes below stay current: nothing stamps
llm_generated_at when bills.summary is written, so a Creator-tab save
moves the summary without moving this key.

Both boxes instead follow their own server value during render, each
guarded so a half-typed edit is never overwritten by a background refresh.

## Why the arguments section has its own header

It reads the bill and organizations straight off page data, taking no
props. Not to be confused with BillCreatorOrgPositionCard, a single-
position card inside BillCreatorLlmSummary.

It has its own headed section, matching LLM summary and Categories, so
"Save Supporting / Opposing Arguments" clearly belongs to the arguments,
not the categories above.
