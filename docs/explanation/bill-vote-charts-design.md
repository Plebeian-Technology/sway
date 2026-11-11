---
mode: explanation
summary: "Why AffinityDistrictChart, DistrictVotesChart, and TotalVotesChart reproduce the exact numbers of the older pie/bubble charts, drawn instead as hand-built bars with no charting library"
status: agent-extracted
related: []
---

# Bill vote chart components (`app/frontend/components/bill/charts/`)

## `AffinityDistrictChart.tsx`

The "district affinity" chart, in the neobrutalist style.

The numbers match the old pie and bubble versions exactly:

```
amount = Number(d.for) - Number(d.against)   (may be negative; NOT clamped)
label  = `D-{number} ({+|}{amount})`
```

Those older charts drew a pie or bubbles. This one draws horizontal bars
growing out from a centre line: net support goes right, net opposition goes
left. Same numbers, and no charting library needed.

At-large districts (district number 0) are left out of all three charts
below, because they skew the visual comparison between districts.

## `DistrictVotesChart.tsx`

One horizontal bar per district, showing how many voted FOR and how many
voted AGAINST.

The numbers match the older version of this chart exactly:

```
for     = Number(d.for || 0)
against = Number(d.against || 0)
```

It walks `score.districts`, the array on `sway.IBillScore`, the same way
the older charts container did. At-large districts (number 0) are left out,
as in `AffinityDistrictChart`, because they distort the comparison between
districts.

## `TotalVotesChart.tsx`

One horizontal bar split between Support and Oppose.

The numbers match the older version of this chart exactly:

```
Support = Number(score.for || 0)
Oppose  = Number(score.against || 0)
max     = Math.max(Support, Oppose)
```
