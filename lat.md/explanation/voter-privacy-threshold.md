# Vote privacy threshold

Votes on legislation are only shown when at least ten distinct users have participated in the vote tally to ensure individual voter privacy and prevent identification in small groups.

## Threshold Mechanics

The threshold is applied across several key areas:

- Bill totals: Exact For/Against counts are displayed only when a bill has ten or more voters. Below that threshold, a placeholder is displayed instead of the counts.
- District splits: Each district with ten or more voters displays its For/Against split as whole-number percentages only. No raw counts are shown for districts. Districts with fewer than ten voters are not displayed.
- Legislator agreement: Agreement scores are displayed as percentages only when at least ten users stand behind the score, calculated only from bills that have at least ten voters in the relevant group (locale-level or district-level).

## Placeholder Behavior

When the threshold is not met, a placeholder component informs the user that visual comparisons will be available once more users have voted. This placeholder includes a sharing/invite link to encourage participation.
