---
mode: reference
summary: Layout, tab/history behavior, and polling/refresh mechanics of LegislatorsListScreen.
status: agent-extracted
related: [docs/explanation/mobile-legislator-components-design.md]
---

# LegislatorsListScreen

`LegislatorsListScreen` (`mobile/src/screens/LegislatorsListScreen.tsx`) is
the list of legislators, with a term toggle. Its layout matches the web
legislators page (`app/frontend/pages/Legislators.tsx`):

- a "Legislators" title
- `LocalePickerSheet`, the native locale selector, which feeds
  `useLegislators(localeId)`
- an empty state when the list has nothing in it, with a "Search again"
  button — except when every known term has finished, where searching again
  cannot help and the copy says the term has ended instead
- a three-way control across the page: Current term | Lifetime | History
  (the web uses a three-way tab strip for this instead — a deliberate
  platform difference)
- a list of `LegislatorCard` rows for Current and Lifetime; History gets its
  own list, flattened so session headings and entries sit in one array
- a 15-second poll through `useFocusedSync`, paused whenever the screen
  loses focus so it does not drain the battery — the bills list has no poll
  at all
- pull down to refresh
- an offline banner when `isOnline` is false

## "Search again"

POSTs to `/user_legislators` with the `sway_locale_id`, which makes the
server work out this locale's legislators for the user again.

## History

History is fetched only the first time the History segment is opened. It is
not part of `refresh()` or the 15-second poll, so those entries never
refetch on that cadence and cannot go stale mid-view.

## Implementation notes

`useFocusedSync` already wraps `useFocusEffect`, so the screen has no
separate `useIsFocused` call, and nothing in this file reads style values
from `tokens.ts` inline.
