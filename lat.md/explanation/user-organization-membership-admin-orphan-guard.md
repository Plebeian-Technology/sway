---
lat:
  mode: explanation
---

# Guarding an organization's last admin

`UserOrganizationMembership` never lets an organization end up with zero active admins, across three different ways a membership row can stop being one: a status update, a role demotion, or an outright destroy.

## Re-activating a removed row instead of creating a new one

The `activate` event's `transition removed: :active` lets re-inviting someone who was previously removed bring their EXISTING row back to life, rather than creating a second one.

The unique index on `(user_id, organization_id)` wouldn't allow a second row for the same pair anyway, so reactivating the old row is the only way a re-invite can actually succeed.

## The update-time guard

`validate :must_not_orphan_org_admin_on_update, on: :update` blocks demoting the organization's only active admin to `standard`, and blocks marking them `removed`.

It runs on every update, but `__only_active_admin?` (below) bails out cheaply, before taking any lock, whenever this row was not an admin to begin with — the common case for most updates.

`must_not_orphan_org_admin_on_update` is a validator, so it returns nothing useful on its own; adding an error with `errors.add(:base, ...)` is what actually makes Rails refuse the save. `throw :abort` does NOT belong here — that mechanism belongs to destroy callbacks, covered next.

## The destroy-time guard

`before_destroy :must_not_orphan_org_admin_on_destroy, prepend: true` has to run BEFORE Rails' `dependent: :destroy` cascade does — destroying a `User`, for instance, walks all of that user's memberships.

`prepend: true` puts this callback at the very front of the `before_destroy` chain, so the guard's `throw :abort` (which IS how a destroy callback cancels a destroy, unlike the validator above) stops the cascade before any related row is touched, not partway through it.

## __only_active_admin?: the shared check both guards call

`__only_active_admin?` is true only when this row WAS the organization's one remaining active admin AND is now losing its admin standing — a demotion, a change to `status: :removed`, or a destroy.

It deliberately reads `role_was` / `status_was` — the values still saved in the database — rather than `admin?` / `status`. By the time a validator runs, ActiveRecord has already written the new values onto the in-memory object, so `admin?` would already answer `false` during a demotion and the guard would skip exactly when it needs to fire. `role_was` on an integer-backed enum column hands back the raw integer, so the comparison checks against the integer value (`self.class.roles["admin"]`) as well as the string, to cover both read shapes.

The count that decides whether this admin is the LAST one runs inside `organization.with_lock`, which locks the organization row — not this membership row — so two transactions demoting different admins on the same organization at the same moment take turns rather than both counting "an admin still standing" and both proceeding. On SQLite in WAL mode, `with_lock` achieves this via `BEGIN IMMEDIATE` against the organization row.

### Why the concurrent-demotion spec is a structural assertion, not a thread race

SQLite's write-ahead log lines writes up one at a time for the whole process, so a spec that actually spawned threads to race two demotes would be flaky rather than deterministic.

`user_organization_membership_spec.rb`'s "serializes concurrent demotes" example instead checks that the lock is actually taken on the parent organization row: it sets the expectation on `admin_a`'s own `organization` object rather than on every `Organization` instance, because `with_lock` is defined in `ActiveRecord::Locking::Pessimistic` rather than on `Organization` itself, which trips up `any_instance_of` stubbing.
