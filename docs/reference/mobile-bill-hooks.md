---
mode: reference
summary: Contract for useBill and the useBills.ts hooks (useBills, useBillCategories, useCachedBill) — what each loads, how caching is split between them, and why useCachedBill exists alongside useBill.
status: agent-extracted
related: []
---

# Mobile bill hooks

## useBill

`useBill` (`mobile/src/hooks/useBill.ts`) loads one bill from
`/bills/:id?with=legislator`. The same Rails endpoint answers both the
website and this app.

You get back the whole payload the website's page would receive, as JSON:
`{ bill, sponsor, bill_score, user_vote, organizations, district_stats? }`.
`BillDetailScreen` picks out the pieces it needs.

On purpose, this hook does not use `useOfflineCache` the way the bill-list
hook `useBills` does. One bill's detail belongs to one screen, and it is
kept current by background polling and live WebSocket updates instead.
There is an offline copy of a single bill, `billCache.get(id)`, and
`BillDetailScreen` could start using it later to show the old copy at once
and refresh behind it. For now the behaviour is: fetch when the screen
opens, refresh on each poll or live update. That matches the website's
`Bill.tsx`, which refreshes the same way.

Cancelling: the request carries an abort signal that `apiClient` honours, so
flipping quickly between tabs cancels the request already in flight instead
of updating a screen that is gone. The resulting "aborted" error is ignored
on purpose.

## useBills

`useBills(localeId)` (`mobile/src/hooks/useBills.ts`) is the list of bills
for one place (city, state or Congress). It shows the copy saved on the
phone right away, then quietly fetches fresh data and swaps it in.

It stitches together `useOfflineCache`, `billCache` (the on-device store),
`apiClient` and `Routes.bills()`. The small adapter strips the cache's
wrapper off each saved row, so callers always get a plain list of bills
whether the data came from the phone's SQLite database or from the network.

`BillRecord` is loosely typed: the server's fields change over time, so
screens read only the keys they know.

Three app-wide rules meet here: anyone may browse without signing in,
saving anything needs a live connection, and lists always paint from cache
first.

`cache` and `fetcher` are built with `useMemo` and kept as the same objects
between renders. `useOfflineCache` watches them, so if they were rebuilt
every render it would fetch in an endless loop. Only a change of `localeId`
should restart it.

The query parameter must be named `sway_locale_id`, not `locale_id`: that
is the name the Rails side reads when it works out which place is being
asked about. Send the wrong name and the server quietly falls back to the
user's home place, so the picker looks broken and reports "no bills found".

## useBillCategories

`useBillCategories(localeId)` is the list of category chips shown above the
bill list. The names come from the server, in the `all_categories` field of
the `/bills` response.

Why it fetches on its own: `useOfflineCache` hands back a list of one type
and has nowhere to carry a second, different value like `all_categories`.
Widening it is off the table, because everything offline depends on that
shape. So this hook makes its own GET to the very same
`/bills?sway_locale_id=N` address. The duplicate round trip is a deliberate
trade: it returns a handful of strings, once per place, and it avoids
splitting the server's bill serializer in two. Do not add a third request,
and do not point this at a new endpoint.

## useCachedBill

This is called `useCachedBill`, not `useBill`, because `hooks/useBill.ts`
already owns that name and returns a different shape (the full page
payload, `BillData`). The two cannot be swapped for each other.
`BillDetailScreen`, the only screen fetching a single bill today, uses
`hooks/useBill.ts`. This one is here for any future caller that wants the
cached-first version instead.

The cache is filed by place, not by bill, so finding one bill means walking
every saved row and matching on id. That is cheap: the cache keeps only
about 20 bills per place.
