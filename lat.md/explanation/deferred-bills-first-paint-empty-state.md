---
lat:
  mode: explanation
---

# Why the bill count / empty-state message lives inside <Deferred>

Explains the bug where an unresolved deferred bills prop looked like zero bills, why the fix keeps the count/empty-state message inside Deferred, and how the regression test mocks it.

## The bug

At first paint, `Bills.tsx` turns the still-unresolved deferred `bills` prop into an empty array (`(bills ??

[]).filter(...)`), so a bill-list layout receives `[]` — and an empty array looks exactly like "no bills" if you only look at its value.

## The fix

The fix is structural, not a value check.

The fix is structural, not a value check: the bill count / empty-state message sits INSIDE `<Deferred>`, so while the data is unresolved only the loading fallback renders, never "No bills found." If this ever regressed to living OUTSIDE `<Deferred>`, the "no bills found" message would render during the unresolved first paint, because `bills` is `[]` at that point.

## How the regression test mocks it

A simple pass-through stub for `Deferred` that always has bills pre-loaded wouldn't catch this bug.

A simple pass-through stub for `Deferred` that always has bills pre-loaded wouldn't catch this bug, so `app/frontend/components/bill/list-layouts/__tests__/deferredFirstPaint.test.tsx` mirrors the real `@inertiajs/react` behavior instead: it shows the fallback while the data prop is unresolved, and shows the children once it resolves. A module-level flag stands in for whether the real page data has arrived yet.
