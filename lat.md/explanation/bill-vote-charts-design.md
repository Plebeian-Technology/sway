---
lat:
  mode: explanation
---

# Bill vote chart components (app/frontend/components/bill/charts/)

Why the total chart shows exact counts while the two district charts show percentages, all drawn as hand-built bars with no charting library.

## AffinityDistrictChart.tsx

The "district affinity" chart draws each district's net lean as a bar growing out from a centre line: net support goes right, net opposition goes left.

The lean is in percentage points, because a district's counts are never sent ([[voter-privacy-threshold#Districts are sent as percentages only]]):

```
amount = forPercent - againstPercent   (may be negative; NOT clamped)
label  = `D-{number} ({+|}{amount}%)`
```

A bar's length is the lean itself, so 100 points fills half the track. Scaling to the widest district would make a two-point lead look like a landslide.

The rows come from [[app/frontend/components/bill/sway_utils/billPositions.ts#selectDistrictVoteSplits]], which leaves out hidden districts and the at-large district. The panel is not drawn at all when no district has a row.

## DistrictVotesChart.tsx

One row per district with two bars, the share that voted For and the share that voted Against, each labelled with its percentage and no count.

It draws the rows [[app/frontend/components/bill/sway_utils/billPositions.ts#selectDistrictVoteSplits]] returns. A district under ten voters has no row, and the at-large district has none either because it repeats the bill total.

## The reader's own district is asked for when the chart is drawn

A reader whose own district is missing from the chart would wonder whether the page forgot them, so the chart adds a row for it that says there are not enough votes yet.

The page does not carry the reader's districts on first load: `districts` is an optional prop. [[app/frontend/components/bill/charts/DistrictVotesChart.tsx#DistrictVotesChart]] asks for it with a partial reload when a signed-in reader's chart is drawn, the same way the district tooltip asks for the roster ([[district-chart-tooltip]]). The list is built from the bill's own locale, not the locale cookie, because the bill page serves a bill from any locale and a reader's district in another locale would otherwise draw a row on a bill that has no such district.

A vote or a pull to refresh replaces every prop and drops `districts` again, so the chart asks again each time that happens: the request latch clears when the request finishes. If the server answers without `districts`, the chart stops asking for the component's life, so an answer that never carries the prop cannot start a request loop.

## TotalVotesChart.tsx

One horizontal bar split between Support and Oppose.

The numbers match the older version of this chart exactly:

```
Support = Number(score.for || 0)
Oppose  = Number(score.against || 0)
max     = Math.max(Support, Oppose)
```
