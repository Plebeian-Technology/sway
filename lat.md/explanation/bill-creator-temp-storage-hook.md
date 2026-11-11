---
lat:
  mode: explanation
---

# useTempStorage: the hide-indicator timer and field-name events

See [[docs/explanation/select-field-autosave-draft-timing-bug.md|select-field-autosave-draft-timing-bug.md]] for why `storeTempData`'s `override` parameter exists and why `storeField` takes the field's NAME rather than a focus event — both are implemented in this hook.

## Why the hide-indicator timer restarts on every blur

The timer that hides the "saved" indicator has to start again on EACH blur, not once when the component first appears.

The old effect had an empty dependency list and set up a single 3-second timer at the start. Any blur after those 3 seconds set `blurredFieldName` with nothing left to clear it, so the indicator stayed on forever.

## Why onBlur is a narrower union than it used to be

`onBlur` is for the fields whose blur really does mean "I have finished with this one": the text boxes, the date inputs and the summary.

The union is back to what those elements are — the button that used to be on it was there for the dropdowns, which now hand over a name instead.

## Why the cleanup effect cancels the hide timer on unmount

When the component goes away, cancel any hide timer still waiting. The timer belongs to the browser, not React, which is why an effect owns it.

## useTempStorage.test.ts notes

The hide timer must restart on every blur — the old effect had an empty dependency array, firing only once at mount, so later blurs had no timer to clear them.

The fake only sets target.name — the one field this hook reads — and casts to the FocusEvent shape the handler expects.

A dead `eslint-disable no-explicit-any` here suppressed nothing — this repo lints with oxlint's `typescript/` rules, not eslint's.

Long after the component appeared: the old one-shot timer would already have fired by now.

A dropdown's "settled" moment isn't a blur event, so the hook also accepts a bare NAME — both paths write the draft and name the field.
