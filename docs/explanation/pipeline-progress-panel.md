---
mode: explanation
summary: "Why PipelineProgress requires onCancelRun instead of a default DELETE fallback, why it opens its own subscription only when the parent doesn't supply one, and how isInFlight/cancellable/isAbandoned are derived from shared status lists."
status: agent-extracted
related: [docs/explanation/pipeline-run-optional-progress-fields.md, docs/explanation/two-tap-confirm-design.md]
---
<!-- vale Vale.Spelling = NO -->

# PipelineProgress mechanics

## Why pickedBillId is threaded through to PipelineTerminalAlerts

What the Run pipeline button will send as `bill_id`, passed through to
PipelineTerminalAlerts so the failure alert can name what that button
covers. Empty means "All Bills".

## Why subscription is optional, with a fallback connection

One connection per run: the parent (BillCreatorPipelineControls) owns the
usePipelineRunSubscription call and passes it down here.

If nothing is passed — used standalone, or from an older screen — this
component opens its own connection instead.

Hooks can't be called conditionally, so even with the parent's connection
we still call this — with runId null, so it opens nothing and we ignore
its result.

## Why onCancelRun is required, not optional

Asks the shell to cancel; this panel only decides IF the operator meant to
(two-tap confirm). Whether that's allowed now, past unsaved edits, is the
shell's call — same as RunConflictBanner. See
[two-tap-confirm-design.md](two-tap-confirm-design.md) for the shared
two-tap hook.

REQUIRED, not optional: an optional prop with a router.delete fallback
would let this panel's Cancel button bypass the shell's unsaved-changes
check again.

## Why the panel updates via PipelineRunChannel, and how cancel works

Panel showing pipeline run progress, updating live via PipelineRunChannel
(through usePipelineRunSubscription). Each channel nudge triggers a
`router.reload` for just the run prop.

Cancelling takes two taps: the first arms a 3-second window, a second tap
inside it sends the DELETE.

## Why the destructured run fields all have defaults

The server sends only DB columns (status, stages, started_at, etc.);
processed/total/phase/eta_seconds/errors/queued arrive later over
PipelineRunChannel.

Defaults here matter: the first render right after a redirect has none of
the channel-only fields yet and must not crash on a missing value. See
[pipeline-run-optional-progress-fields.md](pipeline-run-optional-progress-fields.md)
for the live crash this guards against.

## Why isInFlight uses an allow-list

isInFlightRunStatus uses an allow-list, so an unrecognized status reads as
not-running (the safe default) rather than "not terminal, so must be in
flight".

## Why cancellable checks the shared non-terminal list

Checks PHASE_52_NON_TERMINAL_STATUSES, not just "queued"/"running" — a
stage-named status like fetching_law is still cancellable, and this list
keeps client and server agreeing.

## Why isAbandoned is kept in step with RunConflictBanner

Kept in step with RunConflictBanner above it: without this the same
screen shows a moving bar over the run the banner calls unfinished.

## Why the progress bar only shows while in flight and not abandoned

A bar that cannot move is worse than no bar: it is the thing that reads as
work happening.

## Why the Cancel button reuses the same endpoint for a live run and an abandoned one

Same endpoint either way. "Cancel" reads as stopping work in flight; for
an abandoned run there is none.
