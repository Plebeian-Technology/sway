---
lat:
  mode: explanation
---
# Organizations memberships controller notes

`Organizations::MembershipsController` coordinates member actions, role changes, and view rendering for organization memberships.

## Why leave is separate from destroy

Self-removal via `#leave` moves a membership from active to removed, distinct from administrative member deletion via `#destroy`.

Model validation `must_not_orphan_org_admin_on_update` prevents the last remaining admin from leaving without promoting another admin first. Administrative deletion through `#destroy` removes other users and requires `verify_is_organization_admin!`, which `#leave` does not.

## Why update checks the role before modifying records

Role modification validates the submitted role against `UserOrganizationMembership.roles` before applying changes.

Explicit `nil` verification avoids runtime exceptions from missing keys. The controller pairs a redirect with flash messaging, preserving Inertia post-action redirect semantics.

## The membership detail page

`UserOrganizationMembership.tsx` renders the membership detail view (`GET /organizations/:org_id/memberships/:membership_id`), following role-based tab visibility and URL synchronization.

Visibility rules determine rendered sections:
- Non-admin members receive positions and pending changes tabs.
- Non-Sway organization admins receive positions, pending changes, and members tabs.
- Sway organization admins in production receive a members-only admin layout without tab navigation.

The active detail tab synchronizes with `?org_tab=` through Inertia `router.visit` calls with `preserveState` and `preserveScroll` enabled. Controllers read `org_tab` first and retain `tab` and `tab_key` as legacy aliases; the memberships index preserves its `tab` response prop without adding tab navigation.

In the members tab, [[app/frontend/components/organizations/MembersList.tsx]] exposes role changes and member removal only to admins. Those writes carry the current `org_tab` value and reload only the membership and flash props, keeping the operator on the same tab after the response.

## NewUserOrganizationPosition.tsx, the New Position page

The new position page renders the membership detail view beneath an automatically opened position creation dialog.

`app/frontend/pages/organizations/NewUserOrganizationPosition.tsx` (`GET /organizations/:org_id/positions/new`) renders the underlying membership detail view with the "Add New Position" modal dialog opened on mount. This behavior matches how previous UI implementations layered position creation modals over detail views. Dismissing the dialog navigates back to the membership detail URL.

## MembersList.tsx, the current (V2) members list

The members list component exposes role modifications and member removal controls exclusively to organization admins.

Admin-only controls permit updating member roles via dropdown selectors (`PUT /organizations/:org/memberships/:member_id`) and removing members via action buttons (`DELETE /organizations/:org/memberships/:member_id`). The component preserves legacy role-change and deletion mechanics, including propagating the `?tab=` query parameter and triggering partial reloads of only `membership` and `flash` props.

## MembershipHeader.tsx, the membership detail header

The membership header presents organization identity, assigned role badges, member avatars, and leave actions.

The header displays the organization name, user role as a stamped badge, avatar graphic, and an action to leave the organization. The leave action posts to a route scoped to the current user without requiring client-supplied membership identifiers. The `must_not_orphan_org_admin_on_update` validation surfaces errors via standard application flash banners when an only admin attempts self-removal.

## UserOrganizationMembershipsList.tsx, the memberships dashboard

The memberships dashboard renders a responsive grid of membership cards from user session props.

`app/frontend/pages/organizations/UserOrganizationMembershipsList.tsx` (`GET /users/organization_memberships`) provides the organization memberships dashboard. It consumes `user.memberships` directly from `usePage().props` and displays the collection as a responsive layout of `MembershipCard` components without backend API modifications.

