---
mode: explanation
summary: "Why Organizations::MembershipsController#leave is distinct from #destroy, and why #update validates the role param before touching the record."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# `Organizations::MembershipsController` design notes

## Why `#leave` is separate from `#destroy`

`#leave` is how a member removes themselves from an organization. The
membership's `remove` event moves it from active to removed. A model
validation, `must_not_orphan_org_admin_on_update`, stops the last
remaining admin from walking out and answers with "promote another admin
first". This is not `#destroy` — that action is an admin removing SOMEONE
ELSE, and is gated by `verify_is_organization_admin!`, which `#leave` is
not.

## Why `#update` checks the role before changing anything

`#update` looks the submitted role up against
`UserOrganizationMembership.roles` and checks for `nil` explicitly, rather
than using `fetch`, which would turn an unknown role into a 500. A flash
message plus a redirect matches how the rest of this controller reports
errors — Inertia expects a redirect after a POST, so rendering a bare 422
here would break that expectation.

## `UserOrganizationMembership.tsx`, the membership detail page

`app/frontend/pages/organizations/UserOrganizationMembership.tsx` is the
membership detail page in the current UI (`GET
/organizations/:org_id/memberships/:membership_id`). It follows the same
role-based visibility rules the old UI used:

- Non-admin → positions + pending changes tabs.
- Non-Sway admin → positions + pending changes + members.
- Sway admin in production → members only (no tabs).

The open tab is kept in the URL as `?tab=`, using Inertia's `router.visit(...)`
with `preserveState` and `preserveScroll` (replacing the URL rather than
pushing a new history entry), so switching tabs feels instant.

## `NewUserOrganizationPosition.tsx`, the New Position page

`app/frontend/pages/organizations/NewUserOrganizationPosition.tsx` (`GET
/organizations/:org_id/positions/new`) renders the membership detail
underneath with the "Add New Position" dialog automatically opened,
matching how the old UI layered the new-position modal over the detail
view. Closing the dialog navigates back to the membership detail URL.

## `MembersList.tsx`, the current (V2) members list

Admin-only controls: change role via the Select dropdown (`PUT
/organizations/:org/memberships/:member_id`), remove a member via the
button (`DELETE /organizations/:org/memberships/:member_id`). Preserves
the same role-change and delete behavior as the legacy version, including
echoing the `?tab=` query param back and doing a partial reload of only
the `membership` and `flash` props.

## `MembershipHeader.tsx`, the membership detail header

Shows the organization's name, the user's role (as a stamp badge), an
avatar, and a button to leave the organization.

The leave action posts to a route scoped to the current user — no
membership id needs to come from the client. The `must_not_orphan_org_admin_on_update`
guard shows a flash error if the only admin tries to leave; this
component doesn't handle that messaging itself, it just relies on the
standard flash banner to show it.

## `UserOrganizationMembershipsList.tsx`, the memberships dashboard

`app/frontend/pages/organizations/UserOrganizationMembershipsList.tsx`
(`GET /users/organization_memberships`) is the organization memberships
dashboard in the current UI. It reads the same prop shape the old page
used — `user.memberships` straight off `usePage().props` — and renders it
as a responsive grid of `MembershipCard` tiles. No backend change was
needed.
