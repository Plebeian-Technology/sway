---
lat:
  mode: explanation
---

# Organization's follower-set queries

Explains Organization's raw-SQL UNION follower-set queries (single-org and batch), and how #notifiable_follower_set_for computes the notify set across two sub-populations without N+1 queries.

## follower_set: the one raw-SQL UNION in the codebase

`Organization#follower_set` returns the `Array[Integer]` of user ids who are either active members OR explicit followers of the organization.

It is a raw SQL `UNION` (without `ALL`), which removes duplicates automatically so a user who is both a member and a follower is counted exactly once. Pending and removed memberships are excluded (`status = 'active'`).

This is the only raw-SQL UNION in the codebase — a deliberate exception, justified because a set operation expresses "either of these two sets, deduped" more cleanly in SQL than in Ruby, and the production hardware (a single Raspberry Pi) favors doing the dedup in one query over pulling both sets into Ruby and deduping there.

Because the query is raw SQL, `sanitize_sql_array` with `?` placeholders is MANDATORY for the interpolated `id`; string interpolation of the id value into the SQL text is forbidden.

`#follower_count` (`follower_set.size`) counts everyone in that set, including muted members — muting notifications is not the same as leaving the organization. It is listed in `PUBLIC_FIELDS` so `#to_public_json` includes it.

## follower_counts_for: batching the same query across a list

`Organization.follower_counts_for(org_ids)` computes deduped follower counts for a SET of organizations in ONE query, returning `Hash[org_id => count]`.

The list serializer's path (`#to_public_json` -> `#follower_count` -> `#follower_set`) used to run one raw UNION PER organization, an N+1 across the whole organizations list page. This grouped version wraps the same member+follower UNION in a subquery, dedups `(organization_id, user_id)` pairs across it, then `COUNT(*)` per `organization_id` counts distinct users per org in a single round trip.

The same `sanitize_sql_array` rule applies: placeholders are mandatory for every interpolated id, and the only literal string interpolation allowed is the `"?, ?, ..."` placeholder list itself, built from a count of ids rather than from any value that could carry attacker input.

`Organization#to_public_json` accepts an optional `follower_count:` argument for exactly this reason — the index serializer passes in the precomputed, deduped count from `follower_counts_for` instead of letting `#to_public_json` fall back to running its own `#follower_count` query per row. The single-org show page omits the argument and gets the fallback, since there is no list to batch across there.

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
