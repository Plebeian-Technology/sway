---
mode: reference
summary: "The legacy-parity formulas VoterAgreementChart and VoterDistrictAgreementChart match, and their empty-state conditions."
status: agent-extracted
related: []
---

# Voter agreement chart legacy parity

## `VoterAgreementChart`

A stack of horizontal bars showing the Agreed / Disagreed / Legislator
Abstained / No Legislator Vote counts.

Matches the numbers the old (legacy) `VoterAgreementChart.tsx` computed:

```
Agreed               = scores.count_agreed || 0
Disagreed            = scores.count_disagreed || 0
Legislator Abstained = scores.count_legislator_abstained || 0
No Legislator Vote   = scores.count_no_legislator_vote || 0
max                  = the largest of the four counts above
```

Shows an empty-state message instead when the whole score object is
empty — the legacy version used an `isEmptyScore` check that returns
true when all four counts are zero or missing, and this matches that
behavior.

## `VoterDistrictAgreementChart`

A district-level Agreed vs. Disagreed bar chart.

Matches the numbers the old (legacy) `VoterDistrictAgreementChart.tsx`
computed:

```
agreedScore    = isFinite(scores.count_agreed) ? scores.count_agreed : 0
disagreedScore = isFinite(scores.count_disagreed) ? scores.count_disagreed : 0
```

Shows an empty-state message instead when both counts are 0, matching
the legacy version's check.
