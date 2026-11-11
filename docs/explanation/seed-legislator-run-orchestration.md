---
mode: explanation
summary: "Why SeedLegislator.run has no fallback roster reader, how it tracks seen and unidentified roster entries, and why the reconcile job runs exactly once per locale."
status: agent-extracted
related: [docs/explanation/legislator-person-not-seat.md, docs/explanation/retire-departed-members-safety-design.md]
---

# SeedLegislator.run's per-locale orchestration

## No fallback roster reader

`SeedLegislator.preparer_class_for` turns a declared `roster_source` name
into the reader that understands that source's file shape. There is no
fallback arm: this used to ask the locale which KIND it was, so adding a
city to `locales.json` without saying where its roster comes from read the
file with the curated reader, in the wrong shape.

## Tracking seen identity values

`seen_identity_values` collects the identity VALUE of every entry in the
fresh JSON — regardless of the `seed_or_skip?` guard, and before calling
`seed` (which may leave a record alone if it was hand-edited since the last
seed). The value, not the published id, is compared: a
stored row's `external_id` holds exactly this value, so the two can be
compared directly. The roster-size check counts these values, and
`RetireDepartedMembersService` asks which stored rows are missing from them.

## Unidentified entries and the blank-name convention

`unidentified_entries` collects every entry the roster carried but could not
name a person in. Such an entry adds nothing to `seen_identity_values`, and
the retire pass would read that silence as the sitting member having left. `BaltimoreRefresh` writes the Council President this way on
purpose when Legistar cannot resolve the chair.

An entry that names no person is left alone rather than seeded, for the
same reason: `BaltimoreRefresh` writes the Council President row with a
blank name on purpose when Legistar cannot say who chairs the council, so
that the office never drops out of the roster. Under a seat-keyed identity a
blank name cannot say who holds the seat. Seeding it anyway would write the
blank over the sitting member's name — the same destruction the seat-keyed
identity change is about, arriving by a different road.

## Malformed rows fail loudly, per-row

One malformed row (a missing required `NOT NULL` field, or a key the
preparer expected but did not find) must not kill the whole multi-locale run
with an opaque error — and must not be silently swallowed either.
`SeedLegislator.run` re-raises as `SeedError` with enough identity (locale
and `external_id`) to find the bad row.

## One reconcile enqueue per locale

`ReconcileUserDistrictsJob` is the ONLY thing that reassigns users to
districts. The seeder never writes `user_legislators` or `user_districts`
rows itself, and no `LegislatorTerm` model callback does either. One enqueue
per locale is enough; enqueuing again on a later run is harmless because the
job re-derives everything from each user's stored address.

`ReconcileUserDistrictsJob` walks every user in one locale and hands each
of them to `ReconcileUserDistrictsService`, catching failures per user so
one bad record cannot stop the whole batch. Running it again is harmless:
it re-compares users against districts, so a repeated or partly finished
seed run finds nothing left to change.

It looks at ALL users in the locale on every run. Membership comes from
`user.sway_locales.include?(sway_locale)` — the same address-derived check
`User#default_sway_locale` already uses — rather than from an existing
`user_districts` row. That way a user who has never managed to resolve a
district for this locale still gets reconciled.

This job is the only place per-user error handling lives.
`ReconcileUserDistrictsService` deliberately does not rescue, so its
failures surface here, get logged and sent to Sentry, and the loop moves on
to the next user. The job itself never re-raises.
