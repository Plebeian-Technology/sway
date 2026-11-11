---
lat:
  mode: explanation
---

# Why LlmSummaryQueuedRunNotice exists

`LlmSummaryQueuedRunNotice` is what a bill with nothing on it yet is told while its summary run waits in the queue.

## The silence this fills

A row sits at `pending` from the moment the click lands until a worker picks the job up.

A row that already carries work says so through `LlmSummaryInFlightNotice`; an empty `generating` row has its own panel. An empty `pending` row had a status badge and nothing else — and that badge is a small pill, easy to miss beside a button that has just gone grey for no stated reason.

## It is not a flicker

One regenerate on bill 25-0064 was measured at 116.9 seconds end to end, and this panel only refreshes every five seconds, so the silence lasted minutes, not a render frame.

## The generating panel keeps its own words on purpose

The empty `generating` panel already says a summary is being written, so it has no silence to fill. This notice is about the step BEFORE that one — the queue wait — which nothing described until this notice existed.

## What the system spec does not assert, on purpose

`spec/system/admin_llm_summary_spec.rb` does not assert the Generate button's "Queueing…" word.

That window is the length of one request, so a browser cannot be relied on to catch it, and a gate that samples for a sub-second state is a flaky gate. The component tests (`BillCreatorLlmSummary.test.tsx`) freeze that moment instead. What a browser spec can prove is the durable half — the badge and this notice — which was the half missing before this change.
