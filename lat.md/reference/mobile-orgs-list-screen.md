---
lat:
  mode: reference
---

# OrgsListScreen

`OrgsListScreen` (`mobile/src/screens/OrgsListScreen.tsx`) is the organizations in one locale.

- Built like the bills list, but with no category chips, because organizations are not sorted into categories, and with no filter bar.

- Pinned header: the "Organizations" title. The locale picker is the list header, or sits above the empty state in a scroll view when the locale has no organizations ([[mobile-chrome-and-scroll-layout#Filters live inside the list, not above it]])
- List: `OrgCard` rows; pull down to refresh, and nothing polls in the
  background. Each row's `keyExtractor` includes `user_follows[item.id] ?? "none"` so the card remounts and `useState` picks up the new `initialFollowId` whenever server follow state changes on refresh. `isSignedIn` is inferred from `data?.user_follows !== undefined` (sent only for signed-in users), and `onRequestSignIn` navigates to `"Auth"` on the root navigator when a signed-out user taps Follow.
- Empty: an empty state naming the locale
- Offline: an offline banner when `isOnline` is false
