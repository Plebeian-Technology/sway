---
lat:
  mode: explanation
---

# Theme-driven layout selection on Bill.tsx and Bills.tsx

`Bill.tsx` and `Bills.tsx` each let the active theme decide which layout component to draw via `billLayoutFor` and `billListLayoutFor`. Both pages call `createElement` to resolve the component dynamically at runtime.

The banner and chamber layouts (for both the single-bill and list variants) are loaded on demand with `lazy()`, so their code lives in its own file and only downloads when needed. The `Suspense` fallback is `null` in both cases, because the layout only changes when the theme does: the page is already on screen, so the instant it takes to fetch that file goes unnoticed.

## Why BillOfTheMonth.tsx draws from the same layouts as every other bill

Bill of the Month uses the same set of bill-detail layouts as every other bill rather than hard-coding a dedicated layout. A theme with its own bill layout displays Bill of the Month using that theme.

The locale picker sits outside the layout: it is part of the page frame, not part of presenting a bill.

## Testing billLayoutFor against lazy-wrapped layouts

`billLayoutFor` resolves whether an active theme provides a specialized bill layout or falls back to the default layout.

The chamber and banner layouts load on demand through `React.lazy`, so the registry hands back a lazy wrapper rather than the component module itself, and comparing against the raw component no longer works. The test instead checks that each theme still resolves to its own layout, the same one every time, and never to the default fallback — the same object on every call, since it is a module-level constant, so switching themes and resolving again never rebuilds the layout.

`billListLayoutFor` (the list-page counterpart) works the same way: Chamber and banner list layouts are code-split (loaded lazily with `React.lazy`), so the registry returns a lazy-loading wrapper rather than the actual component — comparing it directly to the raw component with `.toBe` would no longer work. Its test checks each theme still resolves to its own stable, distinct layout that is not the default fallback: each theme gets its OWN layout (a copy-paste registration that points two themes at one component would otherwise pass every other check), and the result stays stable across calls (it's a module-level constant), so re-resolving a theme while the app is running never causes the layout to remount.

## Why BillLayoutProps carries only display data, no fetching

`BillLayoutProps` (`layouts/types.ts`) carries presentation data for bill-detail layouts without performing data fetching. Page-level hooks manage polling and score synchronization and supply the resolved data down.

Per-theme layouts can rearrange this data however they like without re-running those page hooks. The per-theme layouts (`banner`, `ballot`, `cornerstore`, `monochrome`, `service-manual`, `swiss-grid`) are code-split — the browser only downloads a theme's layout code when a user is on that theme. `Bill.tsx` wraps the resolved layout in `<Suspense>`, so callers don't need to care that a layout might load lazily. Any theme absent from `BILL_LAYOUTS` (`sway`) falls back to `DefaultBillLayout`.

## Why VotePanel.tsx's For/Against buttons carry meaning in colour, not a token name

For and Against vote buttons express vote intent through theme color variables rather than static token names. The colors correspond to `--vote-for` and `--vote-against`.

The colors come from `--vote-for` and `--vote-against`, which each theme sets for itself — the ballot theme, for one, votes in flag blue and campaign red rather than the usual green and red.

## Why BallotBillLayout.tsx and CornerstoreBillLayout.tsx look the way they do

`BallotBillLayout.tsx` presents a bill as an official ballot measure with scanner sheet styling, while `CornerstoreBillLayout.tsx` renders the bill as a neighbourhood poster with bold wood-type headlines.

The ballot layout presents the bill as the ballot measure it is. The bill code is the headline, and the long legal title moves down into the body text instead of being set as a huge bold hero. Sections are divided by ruled lines, like a scanner sheet, rather than stacked as cards, and the vote is the fill-in-the-oval control.

The corner-store layout presents the bill as a screen-printed neighbourhood poster. A loud label at the top, a wood-type headline over an offset colour wash, flat blocks with hard shadows, and the poster-block vote control. Unlike the original sketch, the headline is the bill's own short title rather than invented editorial wording — Sway reports on legislation, it does not write slogans about it.

## Why BallotVotePanel.tsx is drawn as a real ballot

`BallotVotePanel.tsx` renders the vote interaction as an authentic ballot sheet where selecting an option marks an oval like a pencil mark and displays a recorded stamp once registered.

The behavior — confirming, coping with being offline, writing the vote straight away and undoing it if the server refuses, clearing caches, and the notification — all comes from `useCastVote`, exactly as in the default `VotePanel`.

## Monochrome, Service Manual, and Swiss Notice bill detail layouts

`MonochromeBillLayout.tsx`, `ServiceManualBillLayout.tsx`, and `SwissGridBillLayout.tsx` structure bill details to reflect their respective civic and editorial design traditions. Each layout uses authentic legislative data and theme tokens.

The monochrome layout treats legislation as a typographic proof sheet. Its sixty-five-character reading measure and IBM Plex Mono metadata strip prioritize continuous reading and linear scrutiny, while high-contrast voting with a hatched against bar makes community sentiment legible without color dependence.

The service manual layout follows the visual language of public service manuals. Its split rail separates summary and public testimony from structured metadata and voting actions, using an accent border callout to guide readers to the plain-language summary first.

The Swiss grid layout organizes bill information into an exposed hairline grid. An index column presents section identifiers drawn from parity copy, pairing each label with its content cell to evoke federal government gazettes.

## Monochrome, Service Manual, and Swiss Notice bill list layouts

`MonochromeBillListLayout.tsx`, `ServiceManualBillListLayout.tsx`, and `SwissGridBillListLayout.tsx` provide theme-tailored list views for legislation directories.

Each list layout adapts the theme's structural principles to browsing, searching, and filtering bills. The monochrome list layout emphasizes an editorial measure with mono identifiers. The service manual layout groups filters in an administrative well with civic tags. The Swiss grid layout aligns filters and bill cards within exposed hairline ledger rows.

