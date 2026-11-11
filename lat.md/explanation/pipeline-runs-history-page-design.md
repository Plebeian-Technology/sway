---
lat:
  mode: explanation
---

# Why the pipeline runs history page exists

`admin/PipelineRuns/Index.tsx` is a read-only history of recent pipeline runs.

It picks up where the Bill Creator's active-run panel leaves off: once a run reaches a terminal status (succeeded, failed, and so on), the `active_global` filter drops it from the WebSocket subscription that panel uses. This page is the only place an operator can see runs older than the one currently in flight.

## Why the list still updates itself

The page ships the newest 50 runs unfiltered, and `STATUS_TONE` colors 9 non-terminal statuses — so a page with no live updates would go stale on a running row, which is never acceptable here.

The fix: subscribe to the in-flight run's `PipelineRunChannel` over ActionCable as the primary source, with a 15-second poll as a fallback, both switched on only when a non-terminal run is in the list; once everything is terminal, the page goes quiet.

## Known limitation

A run started while the operator is looking at an all-terminal page only appears after the next navigation — this page promises to keep the runs it is already showing fresh, not to discover brand-new ones.
