---
lat:
  mode: explanation
---

# Why dismissed paste-summary errors live in a module-scoped WeakSet

Explains why dismissed paste-summary validation errors are tracked in a module-scoped WeakSet keyed by array identity, rather than in component state.

`dismissPasteSummaryErrors` and `arePasteSummaryErrorsDismissed` (`app/frontend/components/admin/creator/paste-summary/dismissedPasteSummaryErrors.ts`) remember which batch of paste-summary validation errors the operator has already waved away, even when the dialog is torn down and rebuilt.

## The rule

A dismissal must not outlive the errors it was about.

Closing the dialog clears the textarea, and the browser's copy of the flash errors is never emptied on its own — the Bill Creator's 5-second poll asks only for the bill, organizations and pipeline-run props, and Rails clearing the flash on its own side does not reach props the browser already holds.

## Why component state was not enough

That dismissal state used to live in the dialog's own `useState`.

But the dialog is rendered from two different places, and they are mutually exclusive branches of one state machine: a `completed` generation (and a `skipped` one that already has a summary) shows the completed view, while every other generation status shows the generate branch and its paste fallback. The same poll that leaves the flash alone re-reads the generation status, so the branch can flip under the operator — React unmounts one dialog and mounts a different component, and state living inside a component cannot survive that.

## Why module scope, and why a WeakSet

Module scope is the smallest scope that does survive a remount.

It is a `WeakSet` rather than a `Set` because the thing being remembered is the errors array itself: once Inertia drops the page props holding that array, the entry disappears on its own, so nothing piles up over a session and no cleanup policy has to be invented.

## Why identity, not content

"The same errors" means the very same array object, on purpose.

A dismissal retires one DELIVERY, not a message: submitting again and failing in exactly the same way produces a fresh array, and that failure has to appear again, or the operator is submitting into silence. `PasteSummaryDialog.test.tsx` pins this with two payloads that are identical in content but separate objects.

## Dismissing an empty list

`dismissPasteSummaryErrors` ignores empty arrays. "No errors" is not something the operator can dismiss, and recording the shared empty-array constant would mark a value that every later render compares against.
