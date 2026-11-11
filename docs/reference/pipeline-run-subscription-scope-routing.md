---
mode: reference
summary: "Catalogs the scope values usePipelineRunSubscription's WebSocket payloads carry, the props each scope reloads, and the hook's return shape."
status: agent-extracted
related: [docs/explanation/pipeline-run-subscription-reload-scoping.md]
---
<!-- vale Vale.Spelling = NO -->

# usePipelineRunSubscription: scope routing and return shape

## Return shape

`usePipelineRunSubscription` subscribes to real-time pipeline run updates
over ActionCable (Rails' WebSocket framework) and returns:

- `connected` — the live WebSocket connection state.
- `downgraded` — flips to `true` after 2 seconds of sustained disconnection.
  Drives the "Live updates paused — polling every 5s" banner in
  `BillCreatorPipelineControls.tsx`.
- `lastDisconnectedAt` — the `Date` of the most recent `disconnected()`
  callback firing; consumers may show it for diagnostics.

On reconnecting after a real disconnect, the hook fires
`router.reload({ only: onlyProps })` so any updates missed during the
outage get caught up immediately. `preserveScroll` and `preserveState`
are left out of that call deliberately — Inertia v2 (`@inertiajs/core`
3.1.1) partial reloads always preserve both scroll position and state,
and its `ReloadOptions` type doesn't even accept those two keys anymore
(an older code review flagged "missing preserveState" here, but that
concern was based on Inertia v1 behavior that no longer applies).

## Payload fields other than `scope`

Every field besides `scope` is optional on `PipelineRunPayload` — the exact
shape varies by which part of the app sent the message. Consumers re-fetch
the authoritative state via a partial reload instead of reading fields
directly off the payload.

## `scope` values

`PipelineRunChannel` marks each message with a `scope` field:

| `scope` | Meaning | Source |
|---|---|---|
| `"run"` | The pipeline run's own status changed | `LegislationPipelineRun`'s `after_commit` callback |
| `"bill"` | One bill within the run changed | `PipelineRunBill`'s `after_commit` callback |
| `"stage"` | Reserved for a future per-stage update broadcast | — |
| absent (`undefined`) | An older-style payload | `PollLegislationPipelineRunJob`, activity-log entries, or webhook-replay broadcasts — still handled as a fallback so a deploy in progress doesn't drop any updates |

## Prop reload routing

- `scope === "bill"`: the reload is narrowed to `BILL_SCOPE_PROPS` ∩ the
  caller's `onlyProps` — the bill grid, the cache panel, and the nested
  `pipeline_run_bills` data under `legislation_pipeline_run`. If the
  caller's `onlyProps` doesn't overlap `BILL_SCOPE_PROPS` at all, the hook
  falls back to reloading the full `onlyProps` set instead of reloading
  nothing.
- `scope === "run"`, `scope === "stage"`, and absent scope: reload the
  full `onlyProps` set.

`BILL_SCOPE_PROPS` (in `usePipelineRunSubscription.ts`):

```
"bill", "pipeline_run_bills", "bill_artifact_mirrors", "legislation_pipeline_run"
```

The `bill_artifact_mirrors` prop key comes from
`BillCreator::ResourceCachePanelSerializer`. The underlying
`BillArtifactMirror` database table was dropped; the prop key is kept the
same so `ResourceCachePanel.tsx` doesn't need to change what shape of data
it expects.

## Why the test file imports statically instead of awaiting per test

`usePipelineRunSubscription.test.ts` imports `PIPELINE_LLM_ONLY_PROPS`
statically, below the vitest-hoisted stand-ins, rather than awaiting it
inside each test body. Awaiting per test body put module loading on the
per-test clock: reading `PIPELINE_LLM_ONLY_PROPS` that way cost 681ms —
most of it pulling a panel this file never renders — and the two slowest
tests in the file were the two that timed out under the verify gate.

## Test coverage notes

The disconnect/reconnect tests cast `result.current` to
`{ downgraded: boolean }` rather than asserting the full
`PipelineRunSubscriptionState` shape, so the test stays resilient if that
shape grows more fields in the future.

The "payload.scope routing" `describe` block checks that the hook reads
`payload.scope` from each incoming message and calls
`router.reload({ only: onlyProps })` for each of the three known scope
values (`"run"`, `"stage"`, `"bill"`). Older-style payloads with no
`scope` key still trigger a reload too, as a backward-compatible fallback.

The `narrowToBillScope` tests (`describe("narrowToBillScope (REVIEW-10
LOW-3)")`) live alongside the hook tests rather than in their own file, so
that if a future cleanup re-inlines this logic back into the hook (a
regression), it gets caught here. They're pure-function tests — no React
rendering, no timers.

The `"reloads include legislation_pipeline_run on scope='bill' with the
production PIPELINE_LLM_ONLY_PROPS tuple"` test (and the narrower
`"includes legislation_pipeline_run (cycle-9 HIGH-1 regression guard)"`
test in the `narrowToBillScope` block) both pin the regression described
above under "Why `legislation_pipeline_run` must stay in the bill-scoped
set". The former imports the same `as const` tuple the production
`BillCreatorPipelineLlm` component uses, so a future regression in that
shape gets caught here instead of by an admin noticing a frozen screen; it
asserts `.toContain(...)` rather than `.toEqual(...)` so that adding more
props to the allow-list later doesn't break the test.
