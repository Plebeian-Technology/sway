---
mode: explanation
summary: "Why the Legislators page switches its Current/Lifetime/History tabs entirely client-side instead of asking the server on every click, unlike Notifications."
status: agent-extracted
related: [docs/explanation/legislators-history-per-locale-state.md]
---

# Why Legislators.tsx switches tabs without a server round trip

The Legislators page (`app/frontend/pages/Legislators.tsx`) has a page-wide
Current term | Lifetime | History switch. Clicking a tab changes nothing but
state in the browser — no trip to the server, because both scores already
arrive in the same payload.

The chosen tab is also copied into `?tab=` using a quiet
`history.replaceState`, so it survives a locale switch: `getLocale` rebuilds
the page from scratch and carries the query string along, and without that
copy, switching locale while on History snapped back to Current term. The
copy happens WITHOUT asking the server: on seeing `?tab=history` the server
sends the history data up front. `window.history.state` itself is left
exactly as it was, because Inertia stores its own snapshot of the page
there so back and forward can restore it.

This deliberately does **not** follow the Notifications page
(`app/frontend/pages/Notifications.tsx`), which asks the server on every tab
click. History data on the Legislators page is fetched the first time its
tab is opened; when `?tab=history` is already part of the request, the
server sends it up front instead, since props marked optional are left out
of ordinary visits.

## The Current | Lifetime toggle and why an open accordion used to close on flip

The "Current term | Lifetime" toggle at the top of the Representatives
list works the same way: by default the page shows tallies for the term a
legislator is serving now, and switching to Lifetime shows those tallies
added up across every term the user has a score for. The toggle only
changes what is displayed — it does not throw anything away, and it goes
both ways.

A bug caught by hand once: flipping between Current and Lifetime must not
close a card whose "Show voter agreement" section is open. Before the fix,
Current and Lifetime were separate panels, so the UI library threw away
the open card on flip and its charts snapped shut. Both views now render
inside one panel, so each legislator card stays the same live component
across the flip and an open accordion survives it.

Concretely: `tab !== "history"` guards a single `<TabsContent key="scores"
value={tab}>` that renders every `LegislatorCard`, with `value` following
the selected tab and `mode` computed from that — never two parallel lists of
cards. Radix throws away the panel that is not showing, so two lists gave
each score its own `LegislatorCard`, and flipping between Current and
Lifetime destroyed whatever the card was keeping track of. One panel with a
fixed key keeps each card alive across the flip.

The term year range shown as small supporting text under the tabs is agreed
wording, not to be embellished: an en dash and no extra words. Legislators
serving in one locale share an election cycle, so the first representative's
term stands in for the whole page — that is why this reads off `reps[0]`
rather than a real day: a real day here would be one member's own.

`spec/system/legislators_term_toggle_spec.rb` pins this: after flipping to
Lifetime, it checks the tab trigger's own `data-state` before checking the
charts panel is still present. "Still open after the flip" is already true
BEFORE the click, so checking the charts panel alone would pass even if
the click did nothing — the trigger's `data-state` is what proves the flip
actually happened, and only once it has does the charts panel still being
there mean the card survived rather than never having moved.

## `LegislatorCard.tsx`'s `mode` and `historyEntry` props

`mode` (`"current"` the default, or `"lifetime"`) is which score scope
this card renders — `user_legislator_score` or `lifetime_score`. A
page-level toggle passes this down so both the score tiles and the
embedded `LegislatorChartsPanel` switch together. Ignored when
`historyEntry` is set.

When `historyEntry` is set, the card renders as a frozen History entry
instead of a live one — the entry's frozen term tallies replace the live
score, the term window shows as supporting text, an "Ended" stamp badge
appears next to the name, and the charts toggle is hidden (a history
entry only ships tallies, with no district/locale breakdown to chart).

## `LegislatorChartsPanel`'s `mode` prop and chart list

`LegislatorChartsPanel` is a container that renders the voter agreement
charts for a given legislator. It shows up to three charts, matching the
mobile app:

1. Your agreement with [name] — `user_legislator_score` (always)
2. District N agreement with [name] — `legislator_district_score`
   (hidden for at-large reps)
3. [city, region, country] agreement with [name] — `legislator_locale_score`

`mode` is which score scope to chart — `"current"` (the default, reads
`user_legislator_score` with unchanged captions) or `"lifetime"` (reads
`lifetime_score`, with a "lifetime" qualifier added to captions). The
Bill page never passes this — it's restricted to current-term scores
only.

`props.sway_locale` is missing on a page rendered outside the sharing
pipeline, so the jurisdiction name isn't guaranteed to be there.
`toFormattedLocaleName("")` returns `""`, which just reads as "agreement with
&lt;name&gt;" — the chart still says what it's charting, just without
naming the jurisdiction it couldn't identify.

## Why `districtLabel` checks `typeof === "number"`

`district.number` is typed as `number`, but can actually be missing at
runtime — a plain `` || `District ${legislator.district?.number}` `` would
render the literal text "District undefined" when `district` exists but
`number` doesn't. Checking `typeof === "number"` catches both `null` and
`undefined` cleanly.

## Mobile: `LegislatorsListScreen`'s term year range

The term's year range, shown as small text under the control
("2025–2027"), works the same way as the web: legislators serving in one
locale share an election cycle, so the first one's term window stands for
the whole page. If that first legislator has no active term — a former
representative — the first segment is labelled with the year range instead
of "Current term": same position, different text.

## Mobile: `LegislatorDetailScreen`'s chart list

`LegislatorDetailScreen` (`mobile/src/screens/LegislatorDetailScreen.tsx`)
shows the same charts, matching `LegislatorChartsPanel` above:

1. the user against this legislator — whenever a score exists
2. the district against this legislator — only when the legislator is not
   at-large, meaning `district.number` is above 0
3. the locale against this legislator — whenever `legislator_locale_score`
   exists

For at-large officials (a mayor or council president, district number 0 or
null) the district totals equal the locale totals, so chart 2 is left out
and the locale chart becomes the second panel.
