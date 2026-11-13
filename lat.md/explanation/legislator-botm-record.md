---
lat:
  mode: explanation
---
# Bill of the Month voting record on the legislator page

The legislator detail page lists the released Bills of the Month that came before this legislator in their terms and chamber, their recorded vote on each, and — for a signed-in visitor — the visitor's vote and whether the two agreed.

Which bills qualify is decided on the server, under [[legislators-controller-design#Bill of the Month voting record lives on the detail payload]]; the page renders the list as sent, so an empty list can mean a new member rather than a jurisdiction with no releases.

[[app/frontend/components/legislators/LegislatorBillOfTheMonthRecord.tsx#LegislatorBillOfTheMonthRecord]] renders the `bill_of_the_month_votes` array that [[legislators-controller-design#Detail page has its own response]] attaches to the legislator prop, newest release first. Its copy lives under the legislators group of [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] so the mobile detail screen can share the same words.

## Release dates are read in UTC

A release date is a calendar date sent as a date-only string, which a JavaScript date reads as midnight UTC; a reader's own zone west of London would show the previous day.

Release dates are not pinned to the first of the month, but on the first that slip also changes the month shown. The month label is therefore formatted with the UTC zone, the same reasoning [[term-window-design#Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day]] applies to term days.

The home feed reads legislator vote dates the same way. The importers parse a date-only vote date into midnight UTC, so [[app/frontend/components/feed/dateGrouping.ts]] treats any item stamped at exactly midnight UTC as a calendar date. Read in local time, such a vote would land a day early, show a clock time nobody recorded, and split the Bill of the Month items of its day into repeated headings.

## Anonymous visitors see only the representative's vote

The visitor's own vote and the agreed or disagreed badge appear only when someone is signed in, because an anonymous visitor has no votes to compare.

A signed-in visitor who has not voted on a bill sees "Not voted" and no alignment badge, since agreement is undefined until both sides have a vote.

## The phone fetches the detail response

The mobile detail screen reads the list response first and then the per-legislator response, because only the latter carries the voting record.

[[mobile/src/hooks/useLegislator.ts#useLegislator]] requests the same detail route the web page renders, and the bearer JSON wraps the record under `legislator` just as the Inertia prop does. The screen overlays that record on the cached list row, so the header, scores and contact rows appear at once and stay put while the request is in flight or after it fails. A response for a different legislator is ignored, and a superseded or unmounted request is aborted and never writes state.

The list row never carries the voting record, so the section reads votes from the detail response alone and keeps "not loaded" apart from "none released". Until the detail arrives it shows a skeleton, and after a failure it shows a load error with a retry, so a slow or failed request is never mistaken for a jurisdiction with no Bills of the Month.

[[mobile/src/components/legislators/LegislatorBillOfTheMonthRecord.tsx#LegislatorBillOfTheMonthRecord]] applies the same UTC and signed-in rules as the web section, using solid stamped badges in place of the web outline badges. A tapped bill opens the bill detail screen inside the Legislators section, so the back button returns to the legislator.
