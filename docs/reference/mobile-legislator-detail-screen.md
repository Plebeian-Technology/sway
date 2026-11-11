---
mode: reference
summary: "Layout, data source, and safety notes for LegislatorDetailScreen. The chart list is documented in legislators-tab-switching-design.md."
status: agent-extracted
related: [legislators-tab-switching-design]
---

# `LegislatorDetailScreen`

`LegislatorDetailScreen` (`mobile/src/screens/LegislatorDetailScreen.tsx`)
is one legislator's page.

The web has no equivalent: there, `legislators#show` re-renders the
legislators index filtered down to a single record. Mobile decides this
layout for itself. `[no-web-counterpart]`

Where the data comes from: the `useLegislators` list hook, picking out the
record whose id matches. There is no separate single-record hook.

Layout:

- Header (`testID=legislator-detail-header`): full name as the heading,
  with an uppercase subtitle
- Score tiles (`testID=legislator-detail-score-tiles`): Agreed, Disagreed
  and No vote, in fixed-width digits so the numbers line up
- Charts panel (`testID=legislator-detail-charts`): always open, no
  toggle — see
  [legislators-tab-switching-design.md](../explanation/legislators-tab-switching-design.md)
  for which charts appear and why
- Contact rows: email and phone, tappable, opened through `Linking`

Safety: the id is only used to find a record in the list already fetched.
An unknown id shows an empty state; it never causes a fetch to an
arbitrary URL.
