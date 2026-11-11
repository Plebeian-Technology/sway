---
mode: explanation
summary: "Frontend design notes for the pending organization position change review flow: the IPendingChange status field's back-compat contract, the double-submit guard, and why reject uses a full redirect."
status: agent-extracted
related: [docs/explanation/position-change-response-shaping.md]
---

# Pending organization change review: frontend design notes

## Why `IPendingChange.status` is optional

`status` (`app/frontend/hooks/users/useUserOrganizationMembership.ts`)
matches the field the server's `to_builder` now sends. Membership
payloads run through the `pending` scope today, so every row a caller
sees is `"pending"`. It stays optional, and lists all three values, so a
future history screen can use the other two without changing this type.
Read `change.status !== "pending"` rather than guessing from whether
`approved_by_id` or `rejected_by_id` is filled in (see below).

`PendingChangeCard.tsx` prefers the server-side `status` enum; the
`*_by_id` booleans are a back-compat fallback for payloads predating the
`status` field.

## Why `handleApproval`/`handleReject` guard against double-submitting

`router.put` and `router.delete` are fire-and-forget, so a double click
would send two requests, and the second one would show a misleading
"already finalized" message. Approve used to be missing this guard, even
though reject already had it.

## Why reject uses a full redirect instead of a partial reload

`handleReject` uses a full redirect (not a partial reload) so the
server's flash routes back through Inertia — partial reloads bypass
flash.

## Why Approve and Reject share one right-aligned container

Approve and Reject share one right-aligned container so `CardFooter`'s
`justify-between` keeps the date left and the actions right across every
admin/finalized state.
