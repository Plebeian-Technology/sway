---
mode: explanation
summary: "Why Bill.tsx and Bills.tsx pick their layout component with createElement and lazy() instead of importing and rendering it directly."
status: agent-extracted
related: []
---

# Theme-driven layout selection on Bill.tsx and Bills.tsx

`Bill.tsx` and `Bills.tsx` each let the active theme decide which layout
component to draw — `billLayoutFor` (single-bill layouts) and
`billListLayoutFor` (bill-list layouts) hand back a component defined once
at the top level of its module, so switching themes picks up a new one
straight away. Both pages call `createElement` instead of writing JSX,
because which component it is only becomes known while the code is running.

The banner and chamber layouts (for both the single-bill and list variants)
are loaded on demand with `lazy()`, so their code lives in its own file and
only downloads when needed. The `Suspense` fallback is `null` in both cases,
because the layout only changes when the theme does: the page is already on
screen, so the instant it takes to fetch that file goes unnoticed.

## Why `BillOfTheWeek.tsx` draws from the same layouts as every other bill

Bill of the Week is the front door of the product, so it draws from the same
set of bill-detail layouts as every other bill instead of hard-coding one. A
theme with its own bill layout shows Bill of the Week that way too. The
locale picker sits outside the layout: it is part of the page frame, not
part of presenting a bill.

## Testing `billLayoutFor` against lazy-wrapped layouts

`billLayoutFor` decides which layout a theme gets: either the theme
supplies a bill layout of its own, built differently, or it falls back to
the default.

The chamber and banner layouts load on demand through `React.lazy`, so the
registry hands back a lazy wrapper rather than the component module itself,
and comparing against the raw component no longer works. The test instead
checks that each theme still resolves to its own layout, the same one every
time, and never to the default fallback — the same object on every call,
since it is a module-level constant, so switching themes and resolving
again never rebuilds the layout.

`billListLayoutFor` (the list-page counterpart) works the same way:
Chamber and banner list layouts are code-split (loaded lazily with
`React.lazy`), so the registry returns a lazy-loading wrapper rather than
the actual component — comparing it directly to the raw component with
`.toBe` would no longer work. Its test checks each theme still resolves to
its own stable, distinct layout that is not the default fallback: each
theme gets its OWN layout (a copy-paste registration that points two
themes at one component would otherwise pass every other check), and the
result stays stable across calls (it's a module-level constant), so
re-resolving a theme while the app is running never causes the layout to
remount.

## Why `BillLayoutProps` carries only display data, no fetching

`BillLayoutProps` (`layouts/types.ts`) is the data a bill-detail-page layout
receives. `Bill.tsx` owns the page-level hooks (polling, score subscription,
freshness) and passes the resolved data down; a layout just displays this
shape without doing any of its own data fetching. Per-theme layouts can
rearrange this data however they like without re-running those page hooks.

`layouts/index.ts`: the layouts for less-common themes (banner, chamber,
ballot, cornerstore) are code-split — the browser only downloads their code
when a user is actually on that theme, so they don't add weight to the
common sway/classic path (which uses `DefaultBillLayout`). `DefaultBillLayout`
loads right away instead, since it's the fallback most users see. `Bill.tsx`
wraps the resolved layout in `<Suspense>`, so callers don't need to care
that a layout might load lazily. Any theme absent from `BILL_LAYOUTS`
(classic, sway) falls back to `DefaultBillLayout`.

## Why `VotePanel.tsx`'s For/Against buttons carry meaning in colour, not a token name

The For and Against buttons carry their meaning in colour: a coloured
outline while untouched, filled in on hover, and filled in for good once the
vote is recorded. The colours come from `--vote-for` and `--vote-against`
(see the [theme variable contract](../reference/theme-token-contract.md)),
which each theme sets for itself — the ballot theme, for one, votes in flag
blue and campaign red rather than the usual green and red.

## Why `BallotBillLayout.tsx` and `CornerstoreBillLayout.tsx` look the way they do

The ballot layout: the bill presented as the ballot measure it is. The
bill's CODE is the headline, and the long legal title moves down into the
body text instead of being set as a huge bold hero. Sections are divided by
ruled lines, like a scanner sheet, rather than stacked as cards, and the
vote is the fill-in-the-oval control.

The corner-store layout: the bill as a screen-printed neighbourhood poster.
A loud label at the top, a wood-type headline over an offset colour wash,
flat blocks with hard shadows, and the poster-block vote control. Unlike
the original sketch, the headline is the bill's own short title rather than
invented editorial wording — Sway reports on legislation, it does not
write slogans about it.

## Why `BallotVotePanel.tsx` is drawn as a real ballot

The ballot-styled vote control. Voting on the same bill as your
representative is the whole point of the product, so it is drawn as the
thing it really is: a ballot line whose oval fills in like a pencil mark,
and which earns a tilted RECORDED stamp once the vote is on the record.

The behaviour — confirming, coping with being offline, writing the vote
straight away and undoing it if the server refuses, clearing caches, and
the notification — all comes from `useCastVote` (see [`useCastVote.ts`
design](user-votes-controller-notes.md)), exactly as in the default
`VotePanel`.
