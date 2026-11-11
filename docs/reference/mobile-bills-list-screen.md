---
mode: reference
summary: "Layout of BillsListScreen and why its active-locale state resyncs from bootstrap without a useEffect."
status: agent-extracted
related: []
---

# `BillsListScreen`

`BillsListScreen` (`mobile/src/screens/BillsListScreen.tsx`) is the list
of past bills. Laid out like the web bills page:

- "Past bills" title from `PARITY_COPY.bills.title`
- `LocalePickerSheet`, the native locale selector, which feeds
  `useBills(activeLocaleId)`
- a "CATEGORIES" label and a strip of category chips that scrolls
  sideways
- a count line from `PARITY_COPY.bills.showingCount` /
  `billsNoneFound`
- a list of `BillCard`s, or an empty-state message when there is nothing
  to show
- pull down to refresh
- an offline banner when `isOnline` is false

Anyone can reach this screen, signed in or not. Voting happens on the
bill detail screen, not here. Nothing polls in the background: pulling
down is the only way to refresh.

The search box filters bill titles on the phone over the list already
fetched. It's styled like `FormField`'s `TextInput`, with no visible
label — the placeholder and the accessibility label do that job, which
is how native search boxes normally work.

## Why the active-locale state re-derives during render instead of in a `useEffect`

When `bootstrap` comes back with a different locale id, the picker resets
to it. This compares against a remembered previous id while rendering —
React's documented way to adjust state when a prop changes — instead of
syncing in a `useEffect`. The behaviour is the same: a new bootstrap id
re-seeds `activeLocaleId`, while a locale the user picked by hand (which
leaves `initialLocaleId` alone) survives re-renders.
