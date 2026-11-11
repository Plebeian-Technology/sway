---
lat:
  mode: explanation
---

# Organization positions membership + IDOR security

`spec/security/organization_positions_security_spec.rb` guards `Organizations::PositionsController`: is the caller a member of the organization named in the URL, and can they reach another organization's rows by guessing an id.

Written alongside `spec/security/organization_position_change_security_spec.rb`.

## The two holes

Analysis of two authorization bypass vectors in organization position management: unverified entity IDs and cross-tenant mutation.

1. `#create`, `#new` and `#update` had no membership check at all — only
   `#destroy` was guarded. Any signed-in user could POST a position and a
   change proposal into an organization they do not belong to, with their
   own name on it.
2. `set_position` called `OrganizationBillPosition.find(params[:id])` without
   limiting the lookup to the organization in the URL, so a member of
   organization A could PUT a change proposal against a position owned by
   organization B just by guessing its bare id. The sibling
   `PositionChangesController#set_change` had already closed the same hole
   with a `.joins`.

## The fix

The fix runs `verify_is_active_member!` on `%i[create new update]` and looks `set_position` up through `organization.organization_bill_positions`. These examples are the net that fails without the fix and passes with it.

## Test-design convention

Each example builds its own data in local variables rather than using `let` or a helper `def`, matching the steep-clean pattern in `organization_position_change_security_spec.rb`.

## Members propose, they never edit directly

Members change their organization's stance on a bill by proposing, never by editing it directly.

Members change their organization's stance on a bill by proposing, never by editing it directly: `#create`/`#new`/`#update` require an active member of this org (`verify_is_active_member!`), and each writes an `OrganizationBillPositionChange` row stamped with the current user. An admin has to approve that change before the org's real position moves — the change row is both the paper trail and the approval queue; the position itself only ever changes through an approved change. `#destroy` is different: admin-only, and it marks the position `active: false` (a soft delete) immediately, with no proposal step (`spec/requests/organizations/positions_spec.rb` pins that).

## Why verify_is_active_member! lives in PositionsController, not the base controller

`verify_is_active_member!` lives in `Organizations::PositionsController` rather than in `Organizations::BaseController` so it does not disturb `verify_is_organization_admin!`.

`verify_is_active_member!` lives in `Organizations::PositionsController` rather than in `Organizations::BaseController` so it does not disturb `verify_is_organization_admin!`, which the `sway:lint:org_admin_guards` check watches for.

## Why set_change reuses a still-pending change instead of always creating a new one

`#set_change` only reuses a change whose `status` is still `:pending`.

A rejected change has no approver either, so without the status filter, the same proposer editing again would land back on the rejected row, overwrite it, and leave it marked rejected — a state the admin's pending list never shows, so their edit would effectively vanish. `status: :pending` is the name of the value; the column stores it as the integer 0.

## Why change_must_not_be_finalized! checks finalized?, not approved?

`#finalized?` is true for both approved AND rejected rows, which is what "no more edits" means here. An earlier version checked only for approval, which let rejected rows slip through and still be edited.

## See also

Related security specifications covering organization role-based access control, tenant boundary enforcement, and audit logging.

- `app/controllers/organizations/positions_controller.rb`
- `spec/security/organization_position_change_security_spec.rb`
- `spec/requests/organizations/positions_spec.rb` (the working paths for an
  active member)
