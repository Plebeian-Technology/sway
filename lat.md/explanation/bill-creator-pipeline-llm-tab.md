---
lat:
  mode: explanation
---

# BillCreatorPipelineLlm mechanics

Why BillCreatorPipelineLlm opens one shared ActionCable connection plus a scoped backup poll, how isRunInFlight/isPollingActive are derived, and why several of its supporting types and props exist the way they do.

## Why this tab is one fixed-order column with a shared connection

The "Pipeline & LLM" tab: a single column of sections in a fixed order (the order was reshuffled once — see each section below).

Opens one ActionCable connection for the whole panel, so a single push refreshes both the pipeline run and the cached-files list.

The "a run is already going" banner is deliberately not here — it lives in BillCreatorShell so it stays visible while switching tabs.

Starts two things:

- One live connection via `usePipelineRunSubscription`. Every push is a
  bare `{event: "webhook"}` nudge; each one refetches the run and
  cached-files list.
- A backup poll, every 5 seconds, for `bill`, the run, and the
  cached-files list — active only while a pipeline run or bill refresh is
  in flight. The live connection is the normal path; this is the safety
  net.

## Why bill_llm_provisioning.llm_generated_at is used as a React key elsewhere

BillCreatorLlmSummary uses llm_generated_at as its React key, so a fresh timestamp rebuilds it from scratch.

That clears its local `editableSummary` text and picks up the new server value after a paste or regenerate.

## Why IPickerBill is a narrow local type

There is one bill picker, drawn by BillCreatorShell above every tab, including this one. A pipeline run covers whichever bill that picker has loaded.

Just the picker fields this file needs; BillCreatorBillPicker.tsx has the full type.

## Why fetched_bills is never actually missing

Every bill file on disk, not just this bill's. The server always sends this from BillsController#edit/#new, so it's never missing — an empty download folder yields an empty array.

## Why bills is reused from the picker's props instead of refetched

The picker's bill list already ships with every render (id + external_id) — reused here for PerBillGrid's external_id → bill.id lookup, instead of asking the server again.

## Why onCancelRun is a prop, not local logic

Handed straight down to PipelineProgress's Cancel button — this tab holds no logic of its own; the unsaved-changes question belongs to the shell, which knows whether the Bill form has edits.

## Why pickedBillId goes through the same shared helper as the controls

Same value BillCreatorPipelineControls posts as `bill_id`, read from one helper so the failure alert can't describe a different button than the one that runs.

## Why the subscription is created here, once, for the whole panel

One connection for the whole panel. It gets the full PIPELINE_LLM_ONLY_PROPS list, so a single trip to the server refreshes both the run and the cached-files data. See [[docs/explanation/pipeline-llm-only-props-membership.md|pipeline-llm-only-props-membership.md]] for why that list holds the entries it does.

## Why isRunInFlight checks a shared non-terminal-status list

While a run is going, `legislation_pipeline_run.status` holds one of several in-progress stage names (extracting_text, summarizing, fetching_bills, etc.) — all of them mean "keep polling".

Polling no longer watches LLM generation status — that panel moved to Summary & Positions with its own connection; this tab polls only while a run/refresh is in flight.

Uses the shared not-yet-finished list instead of hand-listing finished ones — a hand-written check once missed two finished states (`partial`, old `completed`).

That made a done run poll forever, rescanning disk every 5s on the small production host; the same bug on the cancel button was fixed the same way.

## Why isPollingActive doesn't reuse the LLM summary's isPipelineBusy helper

Deliberately not the LLM summary's isPipelineBusy helper, despite the similar question — here `bill_pipeline_refresh` has no declared type, so status is a plain `string | null`.

Loosening that helper to accept a plain string would let a misspelled status slip past the aria-describedby check in two places. Different input types, not duplication to merge.

## Why the backup poll's prop list was merged with the live connection's

Backup polling asks for exactly the props the live connection names — one shared list. These used to be two separate lists.

The poll's shorter list named only 4 of the 7 props: with the connection down, the run selector never got the just-started run, and the stuck/orphan-run chips held stale counts.

A test pins the two tuples equal.

## Why stagesSucceeded/stagesTotal are memoized

Remember the succeeded and total counts so we do not walk the stage list on every render. The list only changes when the server pushes an update.

## Why billIdByExternalId is built from the picker's bill list

Build an external_id → id lookup from the picker's bill list, so PerBillGrid's "View" link can point at the real /bills/:id/edit path.

## Section notes (JSX)

RunSelector: look at any saved run, not just the newest — "Latest run (auto)" follows the newest run as it changes.

Section 2 (BillCreatorPipelineControls): passed the connection state so it doesn't open a second live connection for the same run.

Section 3 (PipelineProgress): shares the same connection state so its "live" dot reflects the real connection status.

Section 4 (ResourceCachePanel): read-only cache view, five rows deep. Wrapped in CollapsiblePanel so operators can fold it away; the browser remembers open/closed state.

Section 4.5 (FetchedBillsPanel): everything on disk across all bills, vs. ResourceCachePanel above (selected bill only) — includes leftovers with no bill record.

Sections 5-6 (LLM summary, organization positions) moved to the separate "Summary & Positions" tab — editing work gets its own page.

## SendingServicesPanel design and untrusted-domain guards

`SendingServicesPanel` displays sender domains capped at `SendingServiceDomain::MAX_PANEL_ROWS` alongside the uncapped `total` count so a truncated list is stated rather than silent.

Because every domain string originates from public testimony submissions, rows and test IDs are keyed by numeric `row.id` rather than by domain text, and domain cells use `break-all` wrapping so operators can inspect the full string. `STAMPS` maps only declared labels without a threshold-based proposal step, `machineSentShare` treats zero letters as `0` to avoid division by zero, `shareSubline` pairs every percentage with its raw counts, and `applyLabel` relies on server props without optimistic state.

## Fetched-bills freshness thresholds

`SEVEN_DAYS_MS` and `THIRTY_DAYS_MS` define the age cut-offs for downloaded bill files in the fetched-bills table.

A bill fetched within seven days indicates active polling, whereas an artifact older than thirty days signals that the upstream fetcher has likely stopped updating it.
