---
mode: reference
summary: "Layout of OrgsListScreen, the organizations-in-one-locale list with no web counterpart."
status: agent-extracted
related: []
---

# `OrgsListScreen`

`OrgsListScreen` (`mobile/src/screens/OrgsListScreen.tsx`) is the
organizations in one locale.

Built like the bills list, but with no category chips, because
organizations are not sorted into categories, and with no filter bar.

- Header: an "Organizations" title and the locale picker
- List: `OrgCard` rows; pull down to refresh, and nothing polls in the
  background
- Empty: an empty state naming the locale
- Offline: an offline banner when `isOnline` is false

`[no-web-counterpart]` — the web has no matching page, so mobile decides
the shape.
