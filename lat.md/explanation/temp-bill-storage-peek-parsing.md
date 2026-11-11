---
lat:
  mode: explanation
---

# Why TempBillStorage is shaped the way it is

`TempBillStorage` manages Bill Creator draft persistence in `localStorage`. Its `peek` method parses stored drafts with total parse guarantees and silences side-effect notifications.

## Reading no longer announces itself

Reading a draft operates quietly without raising notifications.

There used to be a `get()` next to `peek()` that popped a "Loaded Data from Temp Storage" toast on a timer. Its one caller restored the draft while the form was being built, so the toast had to be scheduled out of the render — and because the read and the announcement were the same call, the announcement fired again on every later read. Reading is now separate from notification, and the one restore that needs to announce itself does so once.

## A bad parse returns null on purpose

Draft parsing is total and never throws errors through the render tree.

The parse used to be unguarded, and its caller is a lazy `useState` initializer that runs during render. Any malformed entry under the key threw a `SyntaxError` through `PageErrorBoundary`. Because the reset control lived inside the broken subtree, recovering required browser devtools. Answering `null` on a bad parse costs one unrecoverable draft instead of crashing the entire screen. The guard checks `stored === null` rather than a loose truthiness check so that empty strings parse safely as well.

## The restore runs once in useNewBillInitialValues

Draft restoration initializes state once per mount rather than repeating on property updates.

The restore block previously sat in a `useMemo` keyed on `bill`, which created fresh objects on every Inertia props swap and re-fired notifications repeatedly. A lazy `useState` initializer provides a stable run-once primitive. Announcing data restoration operates as a side effect inside a mount-time `useEffect` hook.

## Why TStoredBillDraft is a Partial

Draft structures represent partial form states because older drafts contain fewer keys than newer forms.

Typing the draft as complete allowed omitted fields to reach the form as `undefined` while the type system promised complete values.

## Why asStoredBillDraft is a shape check

Draft validation verifies that stored data survived as a non-null object rather than enforcing strict schema validation.

Because the application is the sole writer of draft storage keys, validating object shape suffices to guard runtime access without duplicating form schema definitions.
