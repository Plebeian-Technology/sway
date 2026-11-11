---
mode: explanation
summary: "Design rationale for useAddressAutocomplete and the AddressAutocomplete V2 field: ref-only state instead of useEffect, session-token lifecycle, request-id superseding, and error/UI behavior."
status: agent-extracted
related: []
---

# Why `useAddressAutocomplete` is built the way it is

## Why the suggestion shape mirrors the old `use-places-autocomplete` library

`AddressSuggestion` (`app/frontend/hooks/useAddressAutocomplete.ts`)
mirrors the old `use-places-autocomplete` `Suggestion` shape (`place_id` +
`structured_formatting`) so the component and its tests stay agnostic of
the prediction source.

`placePredictionToSuggestion` maps a new Places API `PlacePrediction` to
`AddressSuggestion`, and is exported so the mapping can be unit tested
without standing up the live `google.maps` namespace.

## Why state lives in refs instead of `useEffect`

`useAddressAutocomplete` backs the registration address field. It seeds
the search box from any address already on the form, queries
`google.maps.places.AutocompleteSuggestion` (the replacement for the
deprecated `AutocompleteService`) as the user types, and once the user
picks a suggestion, resolves it to address fields and writes them via
`setData`.

The debounce timer, the Places session token, the id of the in-flight
request, and the `place_id`→`PlacePrediction` map all live in refs —
there's no outside system to subscribe to here, so no `useEffect` is
needed (this codebase prefers to avoid `useEffect` where it isn't
required). A steadily increasing request id lets a later response win
over an earlier, now-outdated one. A single session token spans
everything from the first keystroke to the final selection (Google bills
the autocomplete search and the place-details lookup together as one
"session"), and gets reset after each selection.

`predictionsRef` maps `place_id` to the live `PlacePrediction`, so
`handleSelect` can call `toPlace()` on the exact prediction the user
picked (it carries the session token). `toPlace().fetchFields` closes the
Places session (autocomplete + Place Details billed together); it fetches
only the fields the hook parses.

`AutocompleteSuggestion` requires the "Places API (New)" to be enabled on
the Google Cloud project tied to `VITE_GOOGLE_MAPS_API_KEY`.

## Why the `AddressAutocomplete` component resets state in an event handler, not `useEffect`

`AddressAutocomplete.tsx` (V2 address field for `SwayRegistration`) resets
the highlighted option on search-text change inside the input's change
handler rather than a `useEffect` — this codebase avoids `useEffect` where
a plain handler works.

## Why `form` is typed loosely on `AddressAutocomplete`'s props

`IProps.form` is an Inertia `useForm` instance bound to address-shaped
data (`sway.IAddress` by default, but typed loosely here because the
geocode result writes a `"region"` key that isn't part of `IAddress`).

## Why the component prefers the field-keyed form error

Registration is a single-field (address) form, so any submit error
pertains to this input; the component prefers the field-keyed error, else
the first error in `form.errors`.
