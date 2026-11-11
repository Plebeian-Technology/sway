---
mode: explanation
summary: "Why PasteSummaryDialog's error-dismissal state must survive a remount at its other mount site, and why re-submission tests compare error arrays by object identity."
status: agent-extracted
related: []
---

# PasteSummaryDialog dismissal persistence

This dialog mounts from two different sites (LlmSummaryCompletedView vs.
LlmSummaryPasteFallback), chosen by generation status, which the 5s poll can flip.

A dismissal flag in useState dies on unmount, but the dismissed flash persists on
page.props — remounting at the other site would show the stale report again.

Dismissing hides ONE batch of errors, not all errors forever: the
next rejected submission still has to appear.

The second delivery must carry identical text — the code compares by object identity, not
content, so a text-diff check would hide the realistic re-submit case.

(`app/frontend/components/admin/creator/__tests__/PasteSummaryDialog.test.tsx`)
