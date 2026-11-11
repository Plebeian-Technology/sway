---
mode: explanation
summary: "Why useLocale's locale switch lists refreshProps for a partial Inertia reload instead of doing a full page visit, and what a page gives up by not doing so."
status: agent-extracted
related: [docs/reference/use-locale-hook-contract.md]
---

# Why the locale switch uses a partial reload

`useLocale`'s `getLocale` (`app/frontend/hooks/useLocales.ts`) passes
`only: refreshProps` to `router.get`, which turns the locale switch into a
partial Inertia reload rather than a full page visit. That gets a page
three things a full visit can't:

- The page component stays mounted, so the locale picker isn't rebuilt and
  doesn't lose keyboard focus.
- Props left unnamed keep their current values, so the once-per-session
  shared locale list — which by definition never changes after it first
  loads — never gets re-fetched for no reason.
- Naming a deferred prop pulls it into this same response, so the list
  never blanks out to its `<Deferred>` loading state and doesn't need a
  second round trip to the server. On a slow connection that loading state
  can sit on screen for seconds, so this is the difference between a smooth
  swap and a visibly broken-looking reload.

Pages that name nothing in `refreshProps` keep the original full-page-visit
remount behavior instead. Opting into a partial reload requires knowing
every prop that depends on locale — a page that misses one would end up
showing the previous locale's data under the new locale's name.

## Carrying the query string through a locale switch

`getLocale` copies the page's existing query string (`?tab=`, `?search=`,
and so on) into the switch request — this is the ONE place in the
codebase that switches locales, so any view state stored in the URL
survives instead of silently resetting (for example, the Legislators
page's History tab used to snap back to the Current term tab whenever the
locale changed — see
`docs/explanation/legislators-history-per-locale-state.md`).

## Why `?page=` is dropped, not carried over

`?page=` is not carried over with the rest of the query string. It is a
CUMULATIVE count — "the first N pages of this locale's list" — so it is
tied to whatever list it was originally counted against, and means
nothing in a different jurisdiction. Carrying it over used to mean a
reader five pages into Baltimore's bill list would request roughly 120
Congress bills (about 135KB) on switching, a depth they never asked for
there. This is dropped centrally, in `useLocale`, rather than in each
page, because the same reasoning applies to any list — so a page that
adds pagination later can't accidentally forget to handle this.

## Why scroll position is not preserved across a locale switch

Scroll position is deliberately NOT preserved on a locale switch: a
different jurisdiction means different content, so a scroll offset
measured against the outgoing locale's list means nothing against the
incoming one. Inertia's default behavior of returning the reader to the
top is what's wanted here.

## `onStart` / `onFinish` / `onError` behavior

`onFinish` fires on both success AND failure, and Inertia has already
swapped in the new props by the time it runs — so a completed switch
hands off smoothly to the real locale with no gap in between, and a
failed one drops back to whichever jurisdiction is actually still in
effect, rather than leaving the control showing a switch that never
actually happened.

A switch the server refused used to fail completely silently: `onFinish`
drops the pending id, so the control settles back onto the outgoing
jurisdiction and the page ends up exactly as it started. On a slow
connection that's indistinguishable from a request still being in
flight, and the reader's only way to tell was to manually refresh the
page. Every similar mutation elsewhere on these pages already shows an
error toast (Bills' category toggle and load-more, `useUrlSort`,
`useDebouncedUrlSearch`); since this is the one central place that
switches locales, adding one toast here covers all four pages that have
a locale picker.

Pages that keyed some of their own local state to the switch landing get
to restore it in `handlers.onError` — the switch is optimistic by design
(the pending id is set in `onStart` before the server responds), so
something has to be responsible for undoing it if the switch fails.
