---
lat:
  mode: explanation
---

# Why usePipelineRunSubscription scopes its reloads the way it does

Why usePipelineRunSubscription narrows reloads by scope, requires legislation_pipeline_run in the bill-scoped set, and requires callers to pass onlyProps explicitly.

## Why bill-scoped updates narrow the reload

A run can hold on the order of 166 bills, each flipping status independently.

Reloading every prop in `onlyProps` on every single bill change is noticeably slow in practice, so a `scope === "bill"` update narrows the reload to `BILL_SCOPE_PROPS` instead. A run-level change (`scope === "run"` or `"stage"`) still reloads the full set, because it can affect every panel on the page.

## Why legislation_pipeline_run must stay in the bill-scoped set

`PipelineRunBill#after_commit` (`scope: "bill"`) changes that row's status, and that change shows up in the nested `pipeline_run_bills` collection rendered as part of the `legislation_pipeline_run` prop.

`PipelineRunBill#after_commit` (`scope: "bill"`) changes that row's status, and that change shows up in the nested `pipeline_run_bills` collection rendered as part of the `legislation_pipeline_run` prop — the `PerBillGrid` component reads `run.pipeline_run_bills`.

An earlier version of the narrowing logic dropped `legislation_pipeline_run` from `BILL_SCOPE_PROPS`, so a per-bill status change only refreshed the cache panel (`bill_artifact_mirrors`). The visible per-bill status grid silently froze until the 5-second polling fallback eventually caught it up. `legislation_pipeline_run` was put back to fix this.

## Why onlyProps has no default

`usePipelineRunSubscription` used to default `onlyProps` to `["legislation_pipeline_run"]`.

That silently produced narrower-than-expected partial reloads when a caller — the `BillCreatorPipelineLlm` panel — actually needed the wider `PIPELINE_LLM_ONLY_PROPS` list, which also includes `bill_artifact_mirrors`.

Requiring every caller to pass an explicit prop list removes that trap: a new caller using this hook for a different panel must think through and declare its own set of props, rather than silently inheriting a default sized for a different panel.

## Implementation: refs and timers

`BILL_SCOPE_PROPS` is pulled out of the inline `received` handler so this filtering logic has one named place to live, and can be unit tested without rendering the whole hook (tested in `usePipelineRunSubscription.test.ts`).

A future panel that adds another bill-scoped prop only needs to edit this set.

`onlyProps` is held in a ref (`onlyPropsRef`) so the effect's dependency array can leave it out. An inline array literal passed as a prop gets a new identity on every parent render, which would otherwise resubscribe the WebSocket connection on every render. It's typed as `readonly string[]` so callers can pass either a mutable array or an `as const` tuple (the recommended pattern — see `PIPELINE_LLM_ONLY_PROPS` in `pipelineLlmOnlyProps.ts`). `onlyProps` is deliberately left out of the subscription effect's dependency list for the same reason.

`wasDisconnected` distinguishes "initial mount connect" from "reconnect after disconnect" so the hook only fires the catch-up reload on the latter.

`stateRef` mirrors `state` into a ref so the WebSocket callbacks — which capture their surrounding variables once, at subscription time — can read the latest `downgraded` value without needing to resubscribe. The subscription is created in an effect keyed only on `runId`; `state` is deliberately left out of that effect's dependency list, so without this ref the callbacks would keep seeing stale state forever. On the grace-timer's own state update, `stateRef` is kept in sync immediately so a reconnect callback firing right after can see the downgrade flag without waiting for the mirroring effect to run on the next render.

The catch-up reload on reconnect only fires if the disconnect lasted long enough to actually show the downgraded banner (i.e., the 2-second grace timer fired). A brief hot-reload during development, or a short network blip, doesn't need a reload — the WebSocket subscription re-establishes within the grace window without missing any updates. This narrows the catch-up reload to genuinely sustained outages, and avoids wastefully reloading right as the user navigates away during a brief reconnect. The banner itself waits the same 2 seconds before showing, to avoid flickering on a development hot-reload or a brief network blip.
