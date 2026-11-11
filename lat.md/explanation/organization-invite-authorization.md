---
lat:
  mode: explanation
---

# Organization invite authorization

Accepting an organization invite requires a valid signed token bound to the URL's organization and the signed-in user's email, or a pending membership owned by the caller.

## Invite acceptance is bound to token, organization, and email

[[app/controllers/organizations/membership_invites_controller.rb#MembershipInvitesController#accept]] resolves a signed invite token, checks that its organization matches the route, and compares the invited email with the current user's email.

The token prevents accepting an invite by guessing its row id; the organization check prevents using a real token under a different organization's URL; and the email check prevents a reader who obtained someone else's token from joining as its intended recipient. Numeric membership IDs on `#accept` match only `pending` rows belonging to `current_user`, so a `removed` member receives 404 rather than reactivating without a signed invite.

## Reaccepting an invite restores the existing membership

A user who left an organization keeps the unique membership row for that organization with its role reset to `standard` on removal.

Transitioning a [[app/models/user_organization_membership.rb#UserOrganizationMembership]] to `removed` resets its role to `standard`, and [[app/controllers/organizations/membership_invites_controller.rb#MembershipInvitesController#accept]] resets the role to `standard` and activates the row only when it is not already `active`. The database's one-row-per-user-and-organization rule makes reuse necessary; a removed member does not regain prior admin access from an invite, while an already-active admin who clicks a signed invite link for their own organization retains their admin role.
