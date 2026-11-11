---
lat:
  mode: explanation
---

# Legislators History state is tracked per locale

The Legislators page (`app/frontend/pages/Legislators.tsx`) tracks History tab state per jurisdiction, so each piece of state records which locale it refers to and is read back by comparing against the active locale's identifier.

Plain boolean flags fail when locale switching uses partial reloads: the page does not unmount, so a flag set while viewing one locale persists after switching to another, while `history` is a server prop that the switch does not always refresh.

The rule that History is not fetched again when its tab is reopened in the same session still holds. It applies per locale.

## Why requestHistory is one path for both the first open and a retry

`onError` sets `historyFailedFor` rather than leaving `isHistoryLoading` stuck at true after a network failure or a server error.

Each value records the locale that was in play when the request went out, so an answer that arrives after the reader has switched away is filed under the locale it was requested for and read back as not current, instead of overwriting the active view.

## Switching locale while History is open or closed

Switching locale with History open refreshes history in the switch request (`LOCALE_SWITCH_PROPS_WITH_HISTORY`), ensuring the new locale's history arrives.

Switching with History closed leaves the old locale's data in props, so prior assertions about it reset and the next open queries the server again.

The per-locale identifiers recorded for History state name the locale being switched to, and are set before the server confirms the switch. If the switch fails, the component restores pre-switch identifiers to keep the active locale displayed.

## Invalidating History when active roster changes on poll

When background score polling delivers updated legislator props, the active roster signature is compared to invalidate cached History state if representative terms or statuses change.

Web and mobile Legislators screens derive a stable roster signature from active legislator identifiers, term boundaries, and active status (`[id, active, ended_on, term_start_year, term_end_year].join(':')`). If a background poll detects an altered roster signature within the current locale and History was previously requested, cache invalidation occurs:

- When the History tab is currently active, the screen immediately triggers a re-fetch (`requestHistory()` on web, `fetchHistory()` on mobile).
- When the History tab is inactive, cached tracking identifiers (`historyRequestedFor` and `historyFor`) reset to undefined or null, ensuring that the subsequent tab switch fetches fresh data from the server.
- When polling returns an identical roster signature, cached history state remains untouched without duplicate network fetches.

## Mobile: LegislatorsListScreen's historyRequestedFor

`LegislatorsListScreen` (`mobile/src/screens/LegislatorsListScreen.tsx`) tracks whether the History fetch has been requested to prevent duplicate requests in the same session.

It stores the locale rather than a boolean because the fetch applies to a specific jurisdiction. A plain boolean would persist across locale switches, preventing fetches for subsequent locales and displaying stale entries. When switching locale while the History segment is already open, `handleLocaleChange` passes the new locale id directly to `fetchHistory(id)` because it runs before the re-render that updates the hook's `swayLocaleId`. When a history fetch fails (`historyError && !history`), the screen renders an `EmptyState` with a retry button rather than falling through to an empty list that looks like "no history".

When 15-second background polling via `useFocusedSync` updates the legislators list within the active locale, `LegislatorsListScreen` evaluates the active roster signature against the previously recorded baseline. If the roster changed while the History tab is open, it immediately invokes `fetchHistory()`. If the roster changed while viewing Current Term or Lifetime, `historyRequestedFor` resets to `null`, enabling the next tab transition to fetch fresh historical session entries.

## Mobile: useLegislators and LegislatorsListScreen test notes

Voting history held by a legislator belongs exclusively to the locale for which it was fetched.

Storing the locale rather than a global boolean ensures that voting history entries do not leak across jurisdiction switches in the mobile interface.
