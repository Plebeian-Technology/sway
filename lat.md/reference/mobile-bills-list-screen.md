---
lat:
  mode: reference
---

# BillsListScreen

`BillsListScreen` (`mobile/src/screens/BillsListScreen.tsx`) is the mobile bills browser for both "Past Bills of the Month" and "All Bills" (with legislative session selection). Laid out like the web bills pages:

- `BrandHeader` title from `PARITY_COPY.bills.allBillsTitle` ("All Bills") or `PARITY_COPY.bills.pastBillsOfTheMonthTitle` ("Past Bills of the Month") depending on the active mode
- `SegmentedControl` (`testID="bills-mode-tabs"`) switching between "Past Bills of the Month" and "All Bills" (deep links to `/past_bills_of_the_month` open directly on the "Past Bills of the Month" segment)
- `SwayLocalePickerSheet`, the native locale selector, which feeds
  `useBills(activeLocaleId, options)` and resets the selected legislative session
- `BillsSessionPickerSheet`, shown in "All Bills" mode when `legislativeSessions` are returned by the server, allowing readers to switch between the current and historical sessions
- a "CATEGORIES" label and a strip of category chips that scrolls
  sideways
- a count line from `PARITY_COPY.bills.showingCount` /
  `billsNoneFound`
- a list of `BillCard`s, or an empty-state message when there is nothing
  to show
- pull down to refresh
- an offline banner when `isOnline` is false
- only `BrandHeader` and the offline banner are pinned. The mode control, pickers, search box, sort strip, categories row and count line are the `FlatList` header, so they scroll with the bills ([[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]])
- a tap on the `BrandHeader` title scrolls the list to the top once the list is mounted

- Anyone can reach this screen, signed in or not. Voting happens on the bill detail screen, not here. Nothing polls in the background: pulling down is the only way to refresh.

- The search box filters bill titles on the phone over the list already fetched. It's styled like `FormField`'s `TextInput`, with no visible label — the placeholder and the accessibility label do that job, which is how native search boxes normally work.

## Why the active-locale state re-derives during render instead of in a useEffect

When `bootstrap` comes back with a different locale id, the picker resets to it.

- This compares against a remembered previous id while rendering — React's documented way to adjust state when a prop changes — instead of syncing in a `useEffect`. The behaviour is the same: a new bootstrap id re-seeds `activeLocaleId`, while a locale the user picked by hand (which leaves `initialLocaleId` alone) survives re-renders.
