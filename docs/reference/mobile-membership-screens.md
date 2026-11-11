---
mode: reference
summary: "Layout of MembershipDetailScreen and MembershipsListScreen. The invite-accept-from-a-link behavior is documented in membership-invite-accept-flow.md."
status: agent-extracted
related: [membership-invite-accept-flow]
---

# `MembershipDetailScreen` and `MembershipsListScreen`

## `MembershipDetailScreen`

`MembershipDetailScreen` (`mobile/src/screens/MembershipDetailScreen.tsx`)
is one person's membership of one organization.

Which tabs appear depends on the role, exactly as on the web
(`UserOrganizationMembership.tsx`):

- ordinary member: Positions and Pending Changes (2 tabs)
- admin of a normal organization: Positions, Pending Changes, Members (3
  tabs)
- admin of Sway itself in production: Members only, with no tab strip at
  all

The chosen tab is remembered with `navigation.setParams({ tab })`, which
does the same job as the web replacing the current history entry.

`testID="membership-detail-screen"`.

For how the screen accepts an invitation opened from a universal link, see
[membership-invite-accept-flow.md](../explanation/membership-invite-accept-flow.md).

### Why `isPending` checks `membership?.status` carefully

Membership roles today are only "standard" and "admin". A separate status
field, where it exists, is what marks an invite as pending; there is no
"pending" role value at the moment. So `membership?.status` is checked
carefully: if the field is missing this simply never matches. It is
written this way to keep working once the field does exist.

## `MembershipsListScreen`

`MembershipsListScreen` (`mobile/src/screens/MembershipsListScreen.tsx`)
is the organizations this user belongs to.

Laid out like the web memberships page
(`UserOrganizationMemberships_List.tsx`), in two sections:

1. "Active" — cards that open the membership detail screen
2. "Pending invites" — cards with Accept and Decline buttons, wired up
   through `useInviteAccept`

Declining asks for confirmation in a destructive-action sheet before it
calls `decline()`.

Pull down to refresh. An offline banner shows when there is no
connection. `testID="memberships-list-screen"`.
