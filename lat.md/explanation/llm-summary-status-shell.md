---
lat:
  mode: explanation
---

# Why LlmSummaryStatusShell is built the way it is

Explains why LlmSummaryStatusShell centralizes the pipeline-busy flag.

## billPipelineStatus goes to the shell, not each branch

The pipeline status goes to the SHELL rather than to each branch's button row, because every branch greys out its generate or regenerate button on the same flag.

One notice above the branch covers them all and cannot drift out of step branch by branch.

## isBillPipelineRunning is derived once by the parent

The shell draws a generate button of its own, the one in the out-of-date header, so it needs the same check its children apply.

The parent works this out from the same source rather than the shell recomputing it from `billPipelineStatus`, so the buttons cannot disagree about what "running" means. See [[docs/explanation/pipeline-busy-terminal-status-inversion.md|pipeline-busy-terminal-status-inversion.md]] for the underlying `isPipelineBusy` shared-check story this promise once broke.

## abandoned

The server's judgement that the row is stuck with nothing writing to it. The parent derives it once for every branch, so no regenerate control on this screen can answer differently.

## isGenerationInFlight: greying out the header's button

Grey out the out-of-date header's regenerate button while a summary job is already queued or running, so a flip of the stale flag cannot queue the job twice.

`&& !abandoned` because a stuck row LOOKS queued and is not. On a stale row this button is the only regenerate control there is — `LlmSummaryCompletedActions` hides its own with `{!stale && …}` — and a row regenerated after a fresh pipeline fetch is stale by construction. So this was one of the branches where the server's judgement was published and never read.

## Why the confirm dialog lives in the shell, not the completed view

The out-of-date header's button destroys the current summary, and on an out-of-date row it is the ONLY regenerate button, because `LlmSummaryCompletedActions` hides its own confirmed one with `{!stale && ...}`.

The confirmation lives HERE rather than in `LlmSummaryCompletedView`, because the out-of-date header belongs to the shell and appears on every branch, not only on `completed`.

## Dropping the confirm intent when the screen goes busy

Same reset as the completed view's, applied here so the two cannot drift.

This copy of `isRegenerating` deliberately excludes `runInFlight`, so today it flips only when this operator starts something and the dialog cannot outlive a state nobody here created. That is a property of the flag rather than of this component, and it has already changed once — which is exactly how the sibling acquired the fault.

## busyLabel: Generate vs Regenerate wording

The cover goes up for a first Generate as well as for a Regenerate — `BillCreatorLlmSummary#handleGenerate` sets the same flag — and it read "Regenerating summary…" for both.

`role="status"` means a screen reader says the wrong word out loud on a bill that has never been summarized.

Derived from what is on screen rather than from which button was pressed: the panel under the cover shows the stored summary, so a row holding one really is being summarized again, and a row holding none is being summarized for the first time.

## The inert cover, and the bug it replaced

The cover used to be only a picture.

`absolute inset-0` stops the mouse, but nothing underneath was actually disabled, so Tab still reached — and Enter still triggered — Approve, Reject and Save summary on the covered content while the regenerate request was in flight. `inert` takes the whole subtree out of the tab order, out of the accessibility tree, and out of mouse hit testing, all in one attribute. That is exactly what the cover was only pretending to do.

The out-of-date header used to sit OUTSIDE this wrapper, so the protection covered the shell's children but not the shell's own header — a paid POST to `/regenerate_summary` that the cover greyed out and hid while leaving it reachable by keyboard, announced, and enabled. There is no reason for it to be outside: the cover already sits over it.

The disabled state follows `isGenerationInFlight`, not `regenLoading`. `regenLoading` means "THIS button's own request is in flight" and drives its "Queueing…" label, so widening it would make the button take credit for a generation some other control started. `isRegenerating` is the parent's combined "this screen is busy" flag, which is what `isGenerationInFlight` already says.

## Why the confirm dialog sitting outside inert makes no difference

Sitting outside the `inert` wrapper makes NO difference, and the note that used to be here said it did.

`DialogContent` renders inside `DialogPortal`, so Radix mounts it under `document.body` — where it sits in the React tree has no bearing on whether an `inert` div three levels up covers it. Its sibling in `LlmSummaryCompletedView` is passed in as `children`, i.e. inside the wrapper, and the two behave identically.

So the protection has to be real rather than positional: the dialog is CLOSED while a regeneration is in flight, derived straight from the flag rather than latched in an effect. That removes the case the old note was worried about — a confirm dialog left open and clickable over a screen that is already busy — and it removes it for both siblings, since the completed view now derives its own the same way. See [[docs/explanation/bill-creator-completed-view-layout.md|bill-creator-completed-view-layout.md]] ("LlmSummaryRegenerateConfirmDialog and the shell's inert wrapper") for that sibling.

## The busy overlay's aria-live announcement

This is the ONLY sign on the branch that the screen is busy, and `aria-hidden` used to erase it from the accessibility tree, so a screen-reader user heard nothing at all.

`<output>` has an implicit `role="status"`; `aria-live="polite"` reads it out without taking focus away.

## What LlmSummaryStatusShell is

The shared frame around every branch of BillCreatorLlmSummaryStatus: the out-of-date header, shown when the bill's text has moved on since the summary was generated.

The shared frame around every branch of BillCreatorLlmSummaryStatus: the out-of-date header, shown when the bill's text has moved on since the summary was generated; the branch itself; and a cover that blocks the panel while a regenerate request is in flight.
