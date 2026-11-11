---
lat:
  mode: explanation
---

# Client-side pagination

`usePagination` and `Pagination` split page-at-a-time state from the control
strip that renders it, for admin surfaces that already hold their full
collection client-side and only need to slice it.

`usePagination` (`app/frontend/hooks/usePagination.ts`) owns the page number
and slices the given array; `Pagination` (`app/frontend/components/Pagination.tsx`)
is the button strip, wired to whatever `page`/`pageCount`/`onPageChange` it is
given rather than to the hook directly.

## Clamping the page during render, not in an effect

`usePagination` resets the page to 1 the moment it is out of range, by
checking during render rather than waiting for a `useEffect` to run.

The invariant — page must not exceed `pageCount` — depends only on this
render's `page` and `pageCount`, not on detecting a transition between
renders, so an effect would buy nothing here: no "previous items" to compare
against, and no extra render where a stranded page number would flash on
screen first. It also means the hook only ever reads `items.length`, so a
caller that reconstructs the array on every render (`bills.filter(...)`
inline, say) never triggers a spurious reset — only an actual change in count
does.

The reset always lands on page 1, not the new last page. A shrinking
collection is what a search box on a paged list produces, and resetting to
the start is the same behavior every other search-then-page control in the
app already gives (`useUrlSort`'s consumers, [[bills-category-filter]]).

## Why a hook and a presentational component

`usePagination` takes the caller's (possibly filtered) array and only ever
reads its length, so any of its callers can pass a freshly-filtered
collection each render without extra wiring.

Two of the three callers this was built for hand it a plain array they
already hold in full; a third narrows that array with a search box first.
`Pagination` itself takes `page`, `pageCount`, and `onPageChange` rather than
the collection, so the same control strip renders whether those three values
came from `usePagination` or from a caller managing its own page state (a
server-cursor-paged list, say, would wire the same three props from its own
state). Splitting them lets a caller take just the hook and build custom
markup around it, or take both.

## Windowing the page strip

A button per page breaks at the exact scale this was built for: Baltimore's unscheduled-bills list runs to roughly 189 bills, 38 pages at 5 per page — 38 buttons in one row.

`buildPageWindow` always shows the first page, the last page, and a fixed run of siblings around the current page, replacing everything else with an ellipsis, so the strip's width never depends on `pageCount`. `PAGE_WINDOW_SIBLINGS` sets how many siblings that is; a larger collection only changes what the ellipsis hides, never how many buttons render.

`Pagination.test.tsx` asserts that bound directly — the same relative page position at `pageCount` 38 and `pageCount` 500 renders the same number of page buttons — because a future edit that quietly drops the windowing would otherwise only show up as a visual regression on a locale with enough bills to notice, not as a failing test.

## A cursor-paged list managing its own state

[[activity-log-stream#What the hook owns]] is the caller this file's "Why a hook and a presentational component" section anticipated: a buffer built from repeated cursor fetches, not a full array held up front.

`useActivityLogStream` does not call `usePagination` at all, for exactly that reason — its collection keeps growing.

It still renders `Pagination` with `page`, `pageCount`, and `onPageChange`, computed from that buffer's length and a fixed ten-per-page size, so the same control strip and windowing behavior apply without `usePagination`'s assumption that the whole collection is already in hand.

## Search filters the capped list, not the full table

A caller that already receives a server-capped slice (`SendingServicesPanel`'s `domains`, capped at `SendingServiceDomain::MAX_PANEL_ROWS`) can only filter what it was sent — a row past the cap does not exist client-side to match against.

This is a real gap, not a rounding error: on a bill with more sending-service domains than the cap, a search for a domain outside the capped slice returns nothing. Closing it needs a server-side search endpoint, which is out of scope for a client-side filter built on `usePagination`.

`NewPositionDialog` is the second caller in that position. The
action behind it used to send every bill the locale had ever recorded, each one
costing its own reads for votes, categories and the locale, so the page grew
without bound with the locale's history and any active member could ask for it.
It now sends the current session's bills, most recently introduced first, capped
at the same page size the bills index uses, with those three associations
preloaded. The dialog's search reaches only what it was sent, so an organization
whose subject is an older bill has to reach that bill another way until this
picker gets a server-side search of its own.

## A search that cannot reach every row says so

When the panel holds fewer domains than the server counted, the no-match message names how many were searched and how many were not.

The standing total-count paragraph above the search box carries the same numbers, but an operator reading "No domains match this search" is being answered about the domain they typed, and a general caption further up the panel is not that answer. Read on its own the bare message says the domain is not there, which is a different and stronger claim than the panel is entitled to make — the row may exist and simply rank below the cap, since the cap is by machine-sent letter count and a service that has sent few letters so far sits at the bottom of it. Putting the two numbers in the message itself makes the weaker claim the one the operator actually reads.
