---
lat:
  mode: explanation
---

# Mobile legislator components

See [[docs/reference/mobile-legislators-list-screen.md|LegislatorsListScreen]] for how these components fit into the legislators list screen.

## LegislatorAccountability

The user's votes next to their representative's.

Given the bills the user has voted on AND how the legislator voted on those same bills, it puts an "Aligned" or "Divergent" badge on each one, so the user can see at a glance how their elected official lines up with them.

The data it needs is deliberately simple: the caller hands over a flat array of `{ bill_title, user_support, legislator_support }` rows, so this component knows nothing about how UserVote or LegislatorVote are built. The comparison is just as simple: the same side means Aligned (in the green for-vote colour), a different side means Divergent (in the red against-vote colour).

### Abstain counts as Divergent

A legislator who abstained counts as Divergent, since they did not take the same side the user did. The website judges it the same way.

## LegislatorCard

One legislator on a card, built from the shared Card pieces.

What it shows:

- Header: the avatar and the full name (lg semibold), with the office title below it
  in spaced-out capitals. There is no party badge and no "{title} · {party}" line;
  both were dropped on purpose.
- Body: three score tiles (Agreed / Disagreed / No vote), in fixed-width digits so
  the numbers do not shift about. Each tile label is in spaced-out capitals.
- Footer: a "Show / Hide voter agreement" toggle, but only when there is a score.
- Below the footer: the charts panel, when that toggle is open.

Colours arrive through style classes. Two values are read from tokens.ts instead: the avatar fallback icon, and the primary-blue 5px left edge drawn by the Card ([[mobile-chrome-and-scroll-layout#Cards carry a coloured edge]]).

`mode` chooses which score appears — "current" (the default: how often this user and the legislator agreed) or "lifetime" — and switches the tiles and the charts panel together. It is ignored when `historyEntry` is given. `historyEntry` turns the card into a frozen record of a finished term: the stored tallies stand in for the live score, the term dates appear as supporting text, an "Ended" badge sits beside the name, and the charts toggle disappears, because a history entry carries only flat totals with no district or locale breakdown to chart.

\[platform] that "Ended" badge is a solid-filled StampedBadge, where the website uses a ringed, washed badge. The difference is deliberate — see the comment at the top of StampedBadge.tsx.

### Avatar and name row

Matches the website's LegislatorCard. The party label is left out on purpose.

### "Ended" badge (settled — do not change)

The app uses a solid-filled StampedBadge where the website uses a ringed, washed `Badge variant="stamp"`. That is settled — do NOT change it to the ring-and-wash look here (see the top of StampedBadge.tsx).

### Score tiles

Three score tiles, in fixed-width digits so the numbers stay put.

### History hides the charts toggle

A history entry carries flat totals only, with no district or locale breakdown to chart, so the toggle is hidden entirely — the same condition the website uses.

## LegislatorChartsPanel

A horizontal bar chart drawn by hand in SVG.

What it draws:

- 4 rows: Agreed (the green for-vote colour), Disagreed (the red against-vote
  colour), Legislator Abstained (muted), and No Legislator Vote (muted).
- Each bar's width is its share of the largest row's value.
- The available width arrives through an onLayout callback, so the chart fits
  whatever container it sits in.
- It uses react-native-svg (already a dependency, ^15.15.3) — no charting library.

The counts render in fixed-width digits. Bars are drawn by hand rather than with victory-native or Skia. The three colours come from the current theme through useTheme(): tokens.voteFor, tokens.voteAgainst, and tokens.chartMuted.

### DEFAULT_CONTAINER_WIDTH

Width to assume before onLayout has reported one, as in Jest, which has no layout engine. A real device always measures the view before the first paint; this fallback means the bars show up right away instead of flashing blank.
