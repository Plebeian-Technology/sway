---
lat:
  mode: explanation
---

# The district chart tooltip

The district bars on a bill page name the representative for a district when a reader points at one. That name is the only thing the whole locale roster was ever sent for.

## The roster is fetched when a reader asks for it

`legislators` is an optional Inertia prop, so a full load of a bill page sends nothing, and `DistrictLabel` asks for it by name the first time somebody points at or focuses a bar's label.

The commit-era example used a 535-member US roster serialized on two high-traffic
page loads to label a tooltip most readers never open. The label itself has
never depended on the roster — it is the district's own name — so the bar is
drawn and readable immediately either way, and only the representative's name
waits on the round trip.

One request covers the whole page: the props arrive at the page, not at the
component, so the first bar asked for supplies every other bar's label too. The
component remembers it has asked, so pointing at a second bar before the first
answer lands does not ask again.

The mobile JSON body still includes the roster when a client sends no omission
header, and the phone's bill screens send it, as
[[lazy-inertia-props#Mobile JSON omission is an explicit request]] describes.
The phone therefore never holds the roster and takes its names from
[[district-chart-tooltip#The mobile bill JSON carries the names, the web page does not]].

## Why the tooltip opens on an empty roster

A label whose roster has not arrived still renders as a tooltip trigger, showing that it is being looked up, rather than as plain text.

The trigger is what carries the request, so a label that decided it had nothing
to say would never ask and the tooltip would never appear. Once the roster
arrives, a district with nobody in it falls back to plain text, which is the
answer rather than a wait.

## The mobile bill JSON carries the names, the web page does not

A bearer or JSON bill response adds `legislator_names` to each `bill_score.districts` entry. The Inertia page never does, so the web response and its lazy roster stay as they were.

Touch has no hover, and the phone omits the roster, so the names have to arrive
with something the phone already fetches. Two sources were weighed. Fetching the
roster when a reader taps a row repeats the web's round trip and adds a loading
state per tap. Putting each scored district's names beside its tally adds no
request. A score row exists only for a district that has had a voter, so the
names cover at most the locale's districts. For Congress the roster is 537
rows, roughly 280 KB, while names for all 494 districts add roughly 20 KB, about
7% of that. The names ride the score payload for that reason.

[[app/controllers/bills_controller.rb#BillsController#show]] and
[[app/controllers/bill_of_the_month_controller.rb#BillOfTheMonthController#index]]
pass whether the request is a mobile JSON one through
[[app/models/bill.rb#Bill#render]]. Only then does
[[app/serializers/bill_score_resource.rb#BillScoreResource]] serialize entries
with [[app/serializers/bill_score_district_with_legislator_names_resource.rb#BillScoreDistrictWithLegislatorNamesResource]].
The Inertia branch builds the original four-key
[[app/serializers/bill_score_district_resource.rb#BillScoreDistrictResource]],
so the web entries keep their keys by construction, and request specs pin both
key sets. The key is additive for an older bearer client, which ignores it.

The list holds every legislator whose current term is in that district, sorted
by full name, and is empty when nobody serves it. One query reads the terms for
all scored districts and one preloads their legislators, so the query count does
not grow with the district count. The web narrows its roster to the bill's
legislative session, which differs only for a legislator who began serving after
the session ended: the web label stays plain and the phone names that legislator.

On the phone, [[mobile/src/components/DistrictVotesPanel.tsx#DistrictVotesPanel]]
shows the names as a muted line under a row's two bars, worded as the tooltip
words them: "Representative: Name", or "Representatives: A, B" for several. A
district with an empty list keeps only its label. The line sits in the bar
column, so the label and count columns keep their minimum widths, and it wraps
to two lines before ending in an ellipsis, so large text cannot push the counts
off a narrow row. The by-district chart's spoken summary adds each row's names in
parentheses. The net chart does not repeat them, since the same district is named
a few lines above.
