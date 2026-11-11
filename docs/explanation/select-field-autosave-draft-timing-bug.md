---
mode: explanation
summary: "Why SelectField's temp-storage autosave had to key off the choice event, not blur, and why its tests assert stored payload contents rather than that a callback fired."
status: agent-extracted
related: [docs/explanation/radix-select-keyboard-commit-race.md]
---

# SelectField autosave and the Radix callback-order timing bug

`SelectField` is one of the fields on the Bill form that gets auto-saved to
browser storage via `useTempStorage`, so an operator's in-progress choices
survive an accidental navigation. The unsaved-changes dialog promises the
whole form is recoverable this way — `useTempStorage` writes fields to
storage and `useNewBillInitialValues` reads them back. Sponsor, chamber, and
status (all `SelectField` dropdowns) were the exception: they had no `onBlur`,
so a chosen value really was lost, making the dialog's promise only partly
true. The fix gave the dropdowns the same storage hook the other fields have.

## The first attempt: hanging the save on blur

The first attempt wired the auto-save to the trigger's blur event, following
the pattern used by the plain text and date fields. But Radix moves focus
*into* the listbox the moment a `Select` opens (`<FocusScope
trapped={context.open}>` plus `focusFirst([selectedItem, content])`), which
blurs the trigger. That means the blur fires the instant the operator *opens*
the dropdown — before they have chosen anything. The draft, the "Temporary
Data Stored" toast, and the header's "Stored temporary Bill field: Status"
all described the value about to be replaced, and the real choice only
reached storage on some later, unrelated blur.

The fix hangs the store on the event that means "the operator chose
something" (`onValueChange`), and ignores the blur that opening causes. It
keys off an event *name* rather than a faked focus event, because a name is
what `useTempStorage` actually reads, and a hand-built focus event is a shape
nothing in the real path checks.

## The second bug hiding behind the first: stale payload contents

Once the wiring test above passed, the tests still could not see a second bug
underneath it: they stubbed `onStored` and asserted it
was called with the right *field name*, so they verified the wiring but never
the *payload*. `onValueChange` calls `setData` and then `onStored` in a
single handler. `BillCreatorBillForm`'s `toStore` callback is a
`useCallback` over `[form.data]`, so it closes over `form.data` as it stood
for the render still on screen — and Inertia's `commitData` assigns its ref
and *schedules* the React update, so `form.data` is not replaced until the
handler returns. The store therefore wrote the pre-choice value into storage
while the toast and header both said the new choice had been saved.

The smallest harness that reproduces this is state that updates on the next
render, paired with a store that reads that render's (stale) copy. The
generalizable lesson: a callback-fired assertion can stay green across this
class of bug, because a stub cannot observe a payload it was never handed —
the test has to assert the *contents* of what got stored, not merely that
storage was written to.

See `docs/explanation/radix-select-keyboard-commit-race.md` for a related but
distinct Radix Select timing issue (keyboard commit via Capybara).

## Why SelectField.test.tsx's Select stand-in reproduces Radix's callback order

The three buttons reproduce the ORDER a real Radix Select fires its
callbacks in, which is the whole subject of the timing-bug examples: `onOpenChange(true)`
runs on the trigger's pointerdown, and only then does `FocusScope` move focus
into the listbox and blur the trigger. Choosing fires `onValueChange`;
closing fires `onOpenChange(false)` and returns focus to the trigger, which
is a focus and not a blur.

## Why `toStore` is a plain `useCallback`, not a `useMemo`

A function, not a memo — summaryRef doesn't trigger re-renders, so a memo
keyed on state would be one blur stale. This reads the ref fresh each time
useTempStorage writes.

Spreads the LIVE form.data, not frozen initialValues, so title/link/date
edits land in the draft too — modern fields write via setData, so
navigating away and back keeps them.

Draft carries the published summary it was written against (see
summaryWrittenAgainstRef), so a restore can tell an edit from a later save;
the key is stripped on the way back out.
