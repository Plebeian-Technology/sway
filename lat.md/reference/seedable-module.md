---
lat:
  mode: reference
---

# Seedable: the shared re-seed-or-skip rule

`Seedable` is the shared "should this record be re-seeded or left alone?" rule for every seeder in `db/seeds/models/`. It is included into `SeedSwayLocale` and `SeedLegislator`; `SeedBill` applies it where the data is ingested.

## seed_or_skip? decision table

Evaluation outcomes determining whether records are seeded or skipped based on record state.

| Record state | Result |
| --- | --- |
| New record | seed it (`seed_or_skip?` returns `false`) |
| Existing, `force: true` | seed it (`false`) |
| Existing, `last_seeded_at` nil | seed it — never seeded before (`false`) |
| Existing, `updated_at == last_seeded_at` | seed it — clean (`false`) |
| Existing, `updated_at != last_seeded_at` | SKIP (`true`) — caller logs and early-returns |

- The SKIP case means someone edited the record by hand since the last seed, and re-seeding must not overwrite their change.

## When to call stamp_seeded_at!

`stamp_seeded_at!` must be called AFTER `save!`, with the just-saved record.

- It uses `update_columns` to write `last_seeded_at = record.updated_at` without firing any callbacks — this avoids a second `after_commit` pass and keeps the two timestamps equal.

- After writing the columns, `stamp_seeded_at!` reloads the record so both `updated_at` and `last_seeded_at` come back from the database at the same precision. Without this, an in-memory time (microsecond precision) could be compared against a DB-read value the SQLite adapter truncated, and a clean re-seed would be mis-read as edited-by-hand.
