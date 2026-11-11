---
lat:
  mode: explanation
---

# Organizations base controller membership guards

`Organizations::BaseController` keeps organization membership redirects and prop serialization safe when authorization finds no active membership.

## Why membership redirects check for nil first

Other callers can reach the organization redirect path without first passing through its authorization guard. [[app/controllers/organizations/base_controller.rb]] keeps the no-membership case safe.

The nil check prevents an absent membership from being asked for its id. When no personalized membership page exists, the helper returns to the memberships index.

## Why a missing membership returns a direct 403

An organization-admin check cannot redirect through a membership that does not exist.

When the caller has no organization membership, [[app/controllers/organizations/base_controller.rb#BaseController#verify_is_organization_admin!]] returns a direct forbidden response instead of building a membership URL from a missing row. This includes a Sway admin who has no organization-scoped role.

## Why show requires the caller's own non-removed membership

The membership detail endpoint serves active members and pending invitees while blocking removed members, non-members, and cross-member lookups.

[[app/controllers/organizations/memberships_controller.rb#MembershipsController#verify_own_non_removed_membership!]] checks that `current_user_membership` is `active` or `pending` and matches `params[:id]`, returning 403 for JSON callers or redirecting browser callers to `organization_path(organization)` when unsatisfied. [[app/controllers/organizations/base_controller.rb#BaseController#membership_as_props]] and [[app/controllers/organizations/base_controller.rb#BaseController#pending_changes_props]] require `membership.admin? && membership.active?` before serializing member PII or organization-wide pending changes, and [[app/controllers/organizations/memberships_controller.rb#MembershipsController#working_membership]] scopes lookups to `organization.user_organization_memberships`.
