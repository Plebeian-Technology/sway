---
lat:
  mode: explanation
---

# Bill Creator field components: shared design choices

Why DateField and FieldShell reuse the shared Input/theme-token components, why a cleared date input saves null instead of stopping early, and why SelectField deliberately ignores swayField.multi.

## Why DateField wraps the shared Input component

It puts the browser's own `<input type="date">` inside the shared Input component, so the even-width digits and the dark-mode colours come along for free.

## Why a cleared date input saves null instead of stopping early

A browser date input reports `""` both when the operator clears it and while they are still part-way through typing a date.

Saving null on `""` is the right answer for the stored value, because vote dates change what readers see on a bill. React redraws the input from the form data either way, so a half-typed date simply looks blank until it is complete. The old code stopped early here, which made clearing a withdrawn or vote date snap straight back to the previous value.

## Why FieldShell uses named theme colours

It uses the named theme colours `muted-foreground` and `destructive`, so it reads correctly in dark mode too.

## Why SelectField ignores swayField.multi

It picks ONE value. Picking several at once, which organizations and legislator votes need, is a separate component, so this field deliberately ignores `swayField.multi`.

See [[docs/explanation/select-field-autosave-draft-timing-bug.md|select-field-autosave-draft-timing-bug.md]] for why `SelectField`'s auto-save keys off `onValueChange` rather than blur, and why the trigger's own blur handler (`onTriggerBlur`) only fires for a real focus-out and not the blur Radix causes when the listbox opens.

## How SelectField derives options, tracks open state, and mirrors FormData

`SelectField` derives options from page props only for top-level bill fields (`legislator_id`, `chamber`, `status`), while legislator vote lists live in `BillCreatorLegislatorVotes`.

Listbox open state is tracked in `isOpenRef` rather than React state so `onTriggerBlur` reads the current value synchronously without a one-render lag. `onValueChange` stores a plain string in form state, and a hidden `<input>` mirrors `currentValue` under the same `name` as the Radix trigger button so `new FormData(form)` captures the selected value.
