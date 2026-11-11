---
mode: explanation
summary: "Why NewPositionDialog uses shadcn Select with local filtering instead of react-select, and why closing the dialog navigates back to the membership detail page."
status: agent-extracted
related: []
---

# Why `NewPositionDialog` is built the way it is

`NewPositionDialog.tsx` (the current V2 "Add New Position" dialog) sends
a POST to `/organizations/:org_id/positions` with `{ bill_id, support,
summary }`, matching the legacy payload exactly.

## Why shadcn Select instead of react-select

The bill picker uses the shadcn `Select` component with an inline search
box to filter bills on the client. The `react-select` library was
considered and skipped: the bill list is bounded per locale, so shadcn
`Select` plus local filtering is enough without adding another
dependency.

## Why closing the dialog navigates back to the membership detail page

Closing the dialog sends the user back to the membership detail page via
`router.visit`, so `/organizations/:org_id/positions/new` never gets left
behind as a URL the user could reload into a dead end.
