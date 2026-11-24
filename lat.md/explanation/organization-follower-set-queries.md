---
lat:
  mode: explanation
---

# Organization's follower-set queries

Explains how #notifiable_follower_set_for computes the notify set across two sub-populations without N+1 queries, and why no follower count is computed.

## No public follower count

Sway shows no follower count for an organization, and the public organization payloads carry none.

A public audience count implies that the organization has a following on Sway, which most organizations never joined ([[organization-affiliation-labels]]). With the count gone, the member-or-follower set and its batched count had no reader and were removed; notification fan-out never used them.

## notifiable_follower_set_for: the notify set across two sub-populations

`Organization#notifiable_follower_set_for(change_types)` returns `Array[[Integer, String]]`.

`Organization#notifiable_follower_set_for(change_types)` returns `Array[[Integer, String]]` — `[user_id, cadence]` tuples for everyone who should receive a notification for at least one of the given change types, honoring per-follow mutes and the global defaults of members who never created an explicit follow row.

It combines two sub-populations, deduped on `user_id` (a user in both buckets is counted only through the follow-row branch, which always wins, since an explicit follow row is a more specific preference than a member's global default):

- **(a) Users with a follow row.** Included only if NOT muted for ALL of
  the given `change_types` — that is, enabled for at least one. Their
  cadence comes from the follow row itself. All follow rows for the
  organization load in one query.
- **(b) Active members with NO follow row.** Included only if their global
  default preference is on for at least one `change_type`. Their cadence
  comes from `user.org_position_cadence_default`. Their preference columns
  are batch-loaded in one query with `pluck`, not one query per member.

`pluck` is used rather than loading full `User` records for two reasons: it avoids building `ActiveRecord::Base` objects at all (cheaper for a batch this size), and it avoids `User`'s `after_initialize` webauthn-id callback, which would otherwise fire on every partially-selected row built from a `pluck`-adjacent `select`. `pluck` also returns the enum's string key directly (e.g. `"weekly"`), not the underlying integer, so the tuple's cadence value is ready to use without translation either way.
