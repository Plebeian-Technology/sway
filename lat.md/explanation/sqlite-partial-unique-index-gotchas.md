---
lat:
  mode: explanation
---

# Partial unique indexes on a nullable column

A unique index across a nullable column does not do what it looks like it does on SQLite.

A unique index across a nullable column does not do what it looks like it does on SQLite: SQLite treats `NULL != NULL` in a standard unique index, so two rows that are otherwise identical except both having `NULL` in that column are NOT treated as duplicates — the index lets them both through.

Where a column is nullable because some cases legitimately have no value for it, one unique index cannot express "unique on the full key when the nullable column is present, but also only one row per remaining key when it is absent." Splitting into two partial indexes handles both cases explicitly. `db/migrate/20260511220111_create_bill_artifact_mirrors.rb` worked this out for `bill_artifact_mirrors`, whose `version_id` is nullable because some tiers (e.g. summary) are not version-scoped:

```ruby
add_index :bill_artifact_mirrors, [:bill_external_id, :tier, :version_id],
  unique: true, where: "version_id IS NOT NULL"
add_index :bill_artifact_mirrors, [:bill_external_id, :tier],
  unique: true, where: "version_id IS NULL"
```

The second index drops only the nullable column from the key — not the whole key — so `(bill_external_id, tier)` stays unique among the rows with no `version_id`. Dropping the rest of the key too (a bare unique index on `bill_external_id` alone, say) would reject two legitimately different `tier` rows that both happen to have a NULL `version_id`.

The table has since been dropped by `db/migrate/20260513180001`, but the underlying SQLite behavior — and the two-index fix — recurs for any nullable column inside a composite unique constraint.

## Rails 8.1's change can't always infer down for these

Rails 8.1's single-method `change` DSL cannot always infer the reverse operation for a partial unique index with a named `WHERE` clause.

Writing explicit `up`/`down` methods instead keeps rollback unambiguous across SQLite versions; `drop_table` in `down` cascades the indexes, so the down side stays a single statement.
