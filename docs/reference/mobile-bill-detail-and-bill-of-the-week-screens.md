---
mode: reference
summary: "Layout and behavior of BillDetailScreen and BillOfTheWeekScreen: shared section list, loading/refresh, and the vote-refetch delay. Polling mechanics live in bill-page-polling-props-rationale.md."
status: agent-extracted
related: [bill-page-polling-props-rationale, sway-locale-id-param-cookie-guard]
---

# `BillDetailScreen` and `BillOfTheWeekScreen`

Both screens draw the same section list, top to bottom:

- `BillHeader` — title, sponsor, status
- `VotePanel` — the For / Against buttons
- `BillScoreBar` — how the whole locale voted ("How others voted")
- `DistrictStatsPanel` — the user's own district, plus an Aligned/Divergent
  call
- `BillSummarySection` — the Sway AI summary, short first with a way to
  expand
- `OrgPositionsSection` — "Why support" and "Why oppose" cards from
  organizations
- `HearingTestimonySection` — "Take the next step" button and an in-app
  browser

`BillOfTheWeekScreen` adds a `LocalePickerSheet` (the locale switcher row)
at the top of that list, since it is the headline screen on the Home tab.

Staying current (`useFocusedSync`, the 15-second poll, and the after-vote
refetch delay) is covered in
[bill-page-polling-props-rationale.md](../explanation/bill-page-polling-props-rationale.md).

Loading: a skeleton card while the first fetch is still in flight.
Refresh: pull down to refresh.

## `BillOfTheWeekScreen`'s data source quirks

`isOnline` comes from `useVote()`. `useBootstrap` exposes neither
`isOnline` nor a `refresh`; its refetch entry point is named `refetch`.

`bootstrap` is cast through `unknown` to reach fields the server does send
(`sway_locales`, `locale`) but that the `Bootstrap` interface does not list
yet. `Bootstrap.locale` is typed as `Record<string, unknown>`; it is
narrowed to the `{ id: number, name: string }` shape `LocalePickerSheet`
expects, and the cast is safe at runtime.

The refetch callback is wrapped in `useCallback` with a stable dependency
so re-renders do not pile up extra polling timers inside
`useFocusEffect`.

The timer for the after-vote refetch is kept in a ref so a `useEffect` can
cancel it when the screen goes away: React never looks at what
`handleVoted` returns, so the cleanup has to live in a `useEffect`.

Picking a locale really does switch locale — see
[sway-locale-id-param-cookie-guard.md](../explanation/sway-locale-id-param-cookie-guard.md)
for what `refetch(id)` does.
