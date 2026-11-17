# Voter privacy threshold

To protect individual voter privacy, Sway enforces a strict minimum-voter threshold for revealing aggregated voting data. 

## The ten-voter minimum

Sway displays voting tallies and legislator agreement scores only when at least ten distinct users have voted in the relevant context.

- **Bill totals:** Display exact For/Against counts only once the bill reaches ten voters; otherwise, a placeholder is shown.
- **District splits:** District-level For/Against splits are shown as whole-number percentages for districts with ten or more voters; no counts are shown. Districts with fewer than ten voters are not sent.
- **Legislator scores:** Agreement scores are shown as percentages only when ten distinct users stand behind the score, and only for bills that have reached the ten-voter minimum within the group the score covers (locale or district).

This threshold prevents the inference of individual voting positions in small groups where the total voter count is low.
