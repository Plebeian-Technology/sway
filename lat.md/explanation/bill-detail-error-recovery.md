---
lat:
  mode: explanation
---
# When a bill will not load on the phone

The bill screen's copy for a failed load names a gesture — "Could not load this bill. Pull to refresh." — so the screen has to offer that gesture, and a control for anyone who does not reach for it.

## Reaching a retry when the bill will not load

`mobile/src/screens/BillDetailScreen.tsx` draws the failed state inside a `ScrollView` with a `RefreshControl`, and gives its `EmptyState` a "Try again" control. Both run the same refetch the loaded screen's pull gesture runs.

[[mobile/src/api/client.ts#envelopeFrom]] turns either the JSON:API `errors`
array or the older `error` object into one `ApiRequestError` before
[[mobile/src/hooks/useBill.ts#useBill]] sets the detail screen's error state.
The screen therefore offers the same recovery path for both server envelopes.

The failed state used to be a bare `View`. Nothing scrolled, so the pull gesture the message names did nothing at all on that screen, and there was no button either — the reader's only way back was to leave and come again.

The label is `PARITY_COPY.legislators.historyRetry`, the wording the legislators history tab already uses for the same idea, rather than a second phrase for one action. The `detailError` string itself is unchanged: `spec/requests/bills_parity_copy_spec.rb` pins it, and the gesture it names is now true.

The web has no counterpart. `app/frontend/pages/Bill.tsx` has no failed-load branch, and nothing there renders `PARITY_COPY.bill.detailError`, so this copy and this control are the phone's alone.

## Why the error snapshot stops at the empty state

`mobile/__tests__/screens/BillDetailScreen.test.tsx` snapshots the empty state found by walking the rendered JSON, rather than the whole screen.

A `RefreshControl` is passed to `ScrollView` as an element in a prop, and pretty-format walks that element's own graph when it serializes the node holding it. The walk does not terminate anywhere useful: it ran until the output passed the maximum string length and jest reported `RangeError: Invalid string length`. Reaching the subtree by test id through `screen` does not avoid it either, because a test instance still reaches its whole tree.

The plain JSON node for the empty state carries only its own props, so it serializes in bounded time and pins what a reader of the failed screen actually sees.
