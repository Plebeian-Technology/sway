---
mode: reference
summary: "Catalog of the Legistar MatterHistoryActionId values excluded from Baltimore final-passage detection, and how the included list was verified."
status: agent-extracted
related: [docs/explanation/baltimore-legislator-vote-import.md]
---
# Legistar final-passage action IDs

<!-- vale Vale.Spelling = NO -->

`BaltimoreLegislatorVoteUpdateService::FINAL_PASSAGE_ACTION_IDS` names the
`MatterHistoryActionId` values that count as a final vote on a Baltimore
matter. See
[Baltimore's legislator-vote import](../explanation/baltimore-legislator-vote-import.md)
for how the list is used. This document is the catalog: how the included
list was checked, and every ID that was checked and left out.

## How the list was verified

Checked live against `https://webapi.legistar.com/v1/baltimore`
via `Legistar::Client`: five real matters spanning the
Enacted/Passed/Failed/Adopted terminal statuses were inspected through
`matter_histories`. The included IDs and their meaning are documented inline
next to the `FINAL_PASSAGE_ACTION_IDS` array.

## Explicitly excluded action IDs

Verified as intermediate, committee, executive, or non-vote actions:

| Action ID(s) | Meaning | Why excluded |
| --- | --- | --- |
| 6 | Introduced | Not a vote. |
| 21 | Scheduled for a Public Hearing | Not a vote. |
| 22 | Assigned | Not a vote. |
| 58 | 2nd Reader | Not the final vote. |
| 93, 94, 96 | Recommended Favorably [...] | Committee votes — `MatterHistoryPassedFlag` is misleading here. |
| 30, 31, 50, 51, 52, 61, 101, 104 | "Advanced to..." | Procedural, not the vote itself. |
| 33 | Approved and Sent to the Mayor | Fires AFTER the real vote — verified: gives the wrong date, roughly two weeks late. |
| 18 | Vetoed by Mayor | Executive, not a council vote. |
| 20 | Signed by Mayor | Executive, not a council vote. |
| 63 / `MatterStatusId` 27 | Failed - End of Term | Verified: no vote ever occurred — the term expired. |
| 205, 155, 172, ... | "Refer to \<dept\>" | Referrals, not a vote. |
