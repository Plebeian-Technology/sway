---
lat:
  mode: reference
---

# Voter agreement chart legacy parity

The formulas VoterAgreementChart and VoterDistrictAgreementChart draw from, and their empty-state conditions.

## VoterAgreementChart

A stack of horizontal bars showing the Agreed / Disagreed / Legislator Abstained / No Legislator Vote counts.

- Matches the numbers the old (legacy) `VoterAgreementChart.tsx` computed:

```
Agreed               = scores.count_agreed || 0
Disagreed            = scores.count_disagreed || 0
Legislator Abstained = scores.count_legislator_abstained || 0
No Legislator Vote   = scores.count_no_legislator_vote || 0
max                  = the largest of the four counts above
```

- Shows an empty-state message instead when the whole score object is empty — the legacy version used an `isEmptyScore` check that returns true when all four counts are zero or missing, and this matches that behavior.

## VoterDistrictAgreementChart

A district-level or locale-level Agreed vs. Disagreed bar chart, drawn from percentages.

- Bar width and label: `scores.agreed_percent` and `scores.disagreed_percent`
- No counter is read: [[voter-privacy-threshold#Legislator charts draw percentages or the placeholder]]
- A score with `comparison_suppressed` true, a score with no flag and a missing score all draw the placeholder under `data-testid="voter-district-agreement-chart-suppressed"`
