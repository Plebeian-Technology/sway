---
mode: explanation
summary: "Why selectBillPositions filters and re-scopes the organizations prop the way it does, and why selectUserStanding is shared between the Chamber and Banner bill layouts"
status: agent-extracted
related: []
---

# `app/frontend/components/bill/sway_utils/billPositions.ts`

## `selectBillPositions`

Works out each organization's position on a bill. `positions` is the flat
`organizations` prop sent by `Bill#render` — this bill's active org
positions, with each organization embedded. Positions with no summary are
dropped (there's nothing to show for them). The `bill_id === billId` check
is a safety net, since the data sent to the page is already scoped to one
bill. `supporting` and `opposing` split `all` by which side each
organization takes.

## `selectUserStanding`

Works out how the current user's vote compares to how residents voted
overall. Shared by the Chamber and Banner bill layouts, which use this
exact same logic and differ only in the wording each theme shows. `tally`
is the result of `selectVoteTally`.
