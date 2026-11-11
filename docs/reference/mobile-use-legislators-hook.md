---
mode: reference
summary: Contract for the useLegislators hook — parameters, fetch behavior, and what it deliberately does not do yet.
status: agent-extracted
related: []
---

# useLegislators hook

`useLegislators` (`mobile/src/hooks/useLegislators.ts`) loads `/legislators`,
the same Rails endpoint that answers both the website and the app.

## Parameters

Pass `localeId` in the options object and it is sent as a query parameter, so
the server narrows the list to that place — this is what makes the
place-switcher work. Leave it out, or pass `0`, and the server uses whichever
place the signed-in session belongs to.

## Return value

The hook fetches once on mount and returns a `refresh` function to fetch
again.

## What it deliberately does not do

Results are not saved for offline use. That could be added later with the
shared offline-cache hook (`useOfflineCache`, see
`docs/reference/mobile-offline-cache-hook.md`). For now the legislator list
is short, so refetching every time the screen opens is good enough.

## `lifetime_score`

The same agreement counts as `user_legislator_score`, but added up across
every term this person has served. The server adds them up while answering
the request, not in advance. The keys inside are named identically, so the
charts panel and the score tiles on `LegislatorCard` work unchanged when the
reader switches to the Lifetime view.

## `LegislatorHistoryTerm` and history shape

Past terms are already grouped by legislative session on the server, in the
shape it sends: `{ sessions: [{ session_label, entries: [...] }] }`. The
website is handed the identical shape by the identical serializer — it is
typed there as `sway.legislatorHistory` in `app/frontend/index.d.ts`. Each
entry's `score` is a flat set of tallies, with no district-versus-locale
split, so there is nothing to chart from it. That matches what
`LegislatorCard` expects of a history entry.

## `history` on the `/legislators` response

Every `/legislators` response to this app carries `history`. On the website
the field is lazy — the server only builds it when the page asks for it
during a partial reload. The app has no such thing as a partial reload, so
the server builds it every time. `fetchHistory()` still asks for it with its
own request rather than leaning on the website's lazy behaviour, and is kept
out of `refresh()` and the background poll on purpose: history is finished,
settled data, so refetching it every 15 seconds would be waste. It calls the
same `/legislators` address and keeps only the `history` part. The screen
calls it the first time the reader opens History.

## `waitingForNewTerm`

True when the list is empty because every known term has finished, rather
than because Sway never worked out who represents this person. The two
empty lists read the same but call for opposite things from the reader, so
the screen shows different words and hides "Search again" for the first
one.

## `history` on the hook's return value

Past terms, fetched only when asked for. On purpose, neither `refresh()`
nor the background poll touches this. `LegislatorsListScreen` calls it once
per place, the first time the reader opens the History view. A result
belonging to a different place counts as no result at all here — that
includes the error, so a failure while loading one place's history does not
greet the reader when they move to the next place.

## `fetchHistory`

Say which place to fetch for. Switching places updates state and then
re-renders, so a call made from inside the switch handler would still be
holding the place you are leaving. Naming the place you are moving to is
what lets the History view reload immediately instead of waiting for the
next render.

## `HistoryState`

Every piece of History state is filed together with the URL it came from,
never on its own, and it is only read back while that URL still matches the
one on screen. That is what makes switching places safe: the old place's
entries cannot flash up for even a single frame, and a slow response
arriving after the reader has moved on is thrown away instead of
overwriting what they are actually looking at.
