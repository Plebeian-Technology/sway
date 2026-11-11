---
mode: explanation
summary: "Why SeedBill clamps MAX_SEEDED_BILLS, trims over-cap bills after seeding, and deletes dependent rows before destroying them."
status: agent-extracted
related: []
---

# Why SeedBill caps and trims seeded bills

## Clamping the configured max

`SeedBill.resolve_max_seeded_bills` falls back to the default when the
configured value is zero, negative, or not a number. A 0 (which is also what
`"abc".to_i` returns) would make the trim step below call `offset(0)` and
delete EVERY seeded bill for the locale. This is pulled into its own method
so the clamp can be unit-tested.

## Why the cap needs a trim step, not just a limit

The pipeline creates EVERY bill it fetches. The seed-time cap only stops
re-seeding once a locale already has enough bills, and the final query's
`.limit` only shortens the list `SeedBill.run` returns — neither one limits
how many bills a single run creates. Without a separate trim step, a fresh
dev seed used to flood the database. `SeedBill` deletes all but the
`MAX_SEEDED_BILLS` most recent bills for the locale so the cap actually
holds. This runs only in dev/preview (see `enabled?`), so deleting the
extras is safe.

## Why dependent rows are deleted before the over-cap bills

Four tables point at bills with a foreign key but have no `dependent:` rule
on `Bill`: `user_votes`, `user_legislator_emails`, `user_bill_reminders`, and
`admin_bill_views`. SQLite enforces foreign keys, so destroying an over-cap
bill a dev user has touched (voted on, emailed a legislator about, set a
reminder for, or that an admin viewed) would raise
`ActiveRecord::InvalidForeignKey`. `SeedBill` deletes those rows first — this
runs only in dev/preview (see `enabled?`), so hard deletes are safe. Add to
this list if a new table gains a bills foreign key without a `dependent:`
rule.
