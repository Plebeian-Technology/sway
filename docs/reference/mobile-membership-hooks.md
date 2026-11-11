---
mode: reference
summary: Contract for the mobile organization-membership hooks — useMembership, useMemberships, useOrgPositions, and usePendingChanges — what each loads, and the approve/reject wire contract.
status: agent-extracted
related: []
---

# Mobile membership hooks

## useMembership

`useMembership` (`mobile/src/hooks/useMembership.ts`) loads one person's
membership of one organization, from
`/organizations/:orgId/memberships/:id`.

What comes back: the organization itself, the person's role, the
organization's positions on bills, any changes still awaiting approval,
and, if the person is an admin, the list of members.

The same Rails endpoint serves the website and this app. A request
carrying a login token gets JSON in exactly the shape
`Organizations::BaseController#membership_as_props` builds for the web
page.

Like `useBill`, it keys off its two arguments (`orgId`, `id`), so moving to
a different membership refetches on its own.

## useMemberships

`useMemberships` (`mobile/src/hooks/useMemberships.ts`) is the
organizations the signed-in person belongs to, from
`/users/organization_memberships`.

You get two lists: the ones they have joined, and the invitations still
waiting on them. The same Rails endpoint serves the website and this app; a
request carrying a login token gets JSON shaped as `{ memberships,
pending_memberships }`.

Built the same way as `useLegislators`: state, a refresh function, and a
fetch when the hook first runs. Nothing is saved for offline use, for the
same reason as `useLegislators` — the list is short, so refetching each
time the screen opens is good enough. Caching could be added later if that
changes.

## useOrgPositions

`useOrgPositions(orgId, membershipId)`
(`mobile/src/hooks/useOrgPositions.ts`) is the stances an organization has
taken on bills, as seen through one member's view of it.

Where the data comes from: the positions ride along inside the membership
response at `/organizations/:orgId/memberships/:id`. There is no separate
endpoint that just lists positions, so this hook asks for the membership
and picks the positions out of it.

It also gives you `propose`, which POSTs a new position to
`/organizations/:orgId/positions` and then reloads the list.

## usePendingChanges

`usePendingChanges(orgId, membershipId)`
(`mobile/src/hooks/usePendingChanges.ts`) is edits to an organization's
positions that are waiting for an admin to approve them.

Where the data comes from: the changes ride along inside the membership
response at `/organizations/:orgId/memberships/:id`, the same way
`useOrgPositions` reads its data. There is no endpoint that just lists
them, so this hook asks for the membership and picks the `pending_changes`
out of it.

The server does send who rejected a change and when
(`rejected_by_id`/`rejected_at`), and the full `status` enum
(`"pending"|"approved"|"rejected"`). Today the membership response only
includes changes still waiting, so in practice `rejected_by_id`/
`rejected_at` are always missing or null and `status` is always
`"pending"` — the fields are typed out fully so a future screen showing
past decisions can use the same type without breaking anything.

### Approving

Approving sends `PATCH /organizations/:orgId/position_changes/:id` with an
empty body — no `{ status: "approved" }` — matching what the website does.
The Rails action ignores the body completely: the request method plus the
admin-only guard are what mean "approve". It used to send `{ status:
"approved" }`; that was removed so that if someone later tightens the
server to reject unexpected fields, this app does not quietly stop
working.

### Rejecting

Rejecting sends `DELETE /organizations/:orgId/position_changes/:id`.
Nothing is erased — the server marks the change rejected and records who
did it and when. The app gets an empty 204 response and calls `refresh()`
to reload the membership, exactly as approving does.

`apiClient.delete` throws whenever the server does not answer with
success, including a 422. Nothing is caught here on purpose: the caller
adds `.catch` and shows an alert. The test in
`mobile/__tests__/hooks/usePendingChanges.test.ts` pins that chain, so
breaking it fails CI.

### The already-finalized error

If the change was already approved or rejected, the server answers 422
with `{ error: { code: "already_finalized", message: "Change is already
finalized." } }`. `apiClient` digs the nested `message` out, so
the error thrown here already carries the server's own wording. Neither
`approve` nor `reject` catches it on purpose: the caller is meant to add
`.catch((err) => Alert.alert(err.message))` so the user actually sees what
happened. A Jest test pins that whole chain.
