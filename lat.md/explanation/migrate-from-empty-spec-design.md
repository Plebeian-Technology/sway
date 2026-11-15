---
lat:
  mode: explanation
---

# Building the database from nothing

For months Sway could not reliably build its database from nothing, and nothing noticed.

## The gap nothing walked

The machine serving the public never re-runs a migration it has already run.

The check against a copy of the real database replays only the ones still waiting on it. The test database is built by loading `db/schema.rb` rather than by running anything. Every existing check looked at a database that already existed — the one path nobody walked was the one you walk when setting up a new machine, or recovering from a lost one.

## The failure pattern

Building a database from nothing on a new host can stop partway through the migration chain.

Both had the same cause: a migration that names one of the app's model classes, where that class later grows a field stored in a column some later migration adds. Run in date order from nothing, the class cannot finish loading at the moment the migration needs it, and everything after it is cancelled.

The fix for a migration hitting this is to give it its own bare stand-in class that knows nothing but the table name, the way `db/migrate/20260420000001_normalize_user_phones.rb` does, rather than referencing the app's live model class.

`db/migrate/20260528000001_create_admin_settings.rb` broke this way once: `AdminSetting` gained a validation whose column a LATER migration added, so creating the seed row failed when building a database from nothing. `db/migrate/20260813120000_create_replication_heartbeats.rb` follows the same stand-in-class fix for the same reason, inserting its seed row through a bare `MigrationReplicationHeartbeat` rather than the real `ReplicationHeartbeat` model.

`spec/migrations/migrate_from_empty_spec.rb` runs the real deploy command (`db:migrate:with_data`) against an empty database in a throwaway folder, in a separate process — a test that swaps the database out from under itself has its own well-documented ways of lying (see [[docs/explanation/production-snapshot-deploy-rehearsal-harness.md|the production snapshot harness]], which shares that separate-process design for the same reason).

## Why the schema-file check compares mtimes, not contents

Applying migrations normally rewrites `db/schema.rb` and `db/data_schema.rb` from the database that was just migrated — in this spec, a throwaway one.

`config/environments/test.rb` turns that off, and the spec checks that the setting held.

`db/schema.rb` and `db/data_schema.rb` are both authored from development on purpose, so a rewrite from a throwaway migration run must never land in the tracked copies — removing the setting fails the spec by name rather than quietly rewriting them.

The check is on when the files were last written, not on what is in them. Comparing the text is nearly blind: whenever the two files are already current, a dump of the throwaway database reproduces them byte for byte, so the rewrite leaves no trace to compare. Measured: with the setting removed, both files came back identical and both had been written. The only case a text comparison would catch is a file that was already out of date, where the rewrite would silently paper over the staleness instead of reporting it.

Anything that did get overwritten is put back first, so a missing setting costs a red test and nothing else.

## Re-reading columns mid-chain

A production boot caches model columns from the pre-migration schema — eager load and boot-time backfill initializers touch these classes — before `db:migrate:with_data` runs.

A migration positioned after schema migrations that add or change columns on models it writes through, in the same deploy, writes through that stale class-level cache instead. That raises `MissingAttributeError` (caught by the `production_migrate_with_data_task_spec` rake-task replay); `insert_all` against a stale shape would be worse.

`db/data/20260711000004_convert_duplicate_legislators_to_terms.rb` hit this: it runs after the schema migrations that add `legislators.sway_locale_id` and recreate `user_districts` in the same deploy. Its fix — call `reset_column_information` on every touched model at the top of `#up` — re-reads every touched model's columns from the live, mid-chain schema before writing. This is the alternative to the bare stand-in class above: use it when the migration needs the model's real behavior (associations, scopes), not just its table name.

## Why the migration runs through Sway::Subprocess.capture3, not Open3

`/usr/bin/env` sets the child's variables without a shell, so nothing here is ever parsed as a command. `Sway::Subprocess` refuses shell strings for the same reason and takes no variables of its own.

It's `Sway::Subprocess` rather than `Open3`, which the neighboring replay spec (the production snapshot harness) uses, because it is the only one of the two that gives up. A migration that hangs would otherwise hang the whole suite with it, with nothing to say why.

`SWAY_ALLOW_HOST_RAILS` is what `config/boot.rb` wants before it will start outside the container; it is ignored inside one, so this works either way.

## Comparing a migrated table with db/schema.rb

The same spec compares the `legislator_votes` table its throwaway run built with the one the test database loaded from `db/schema.rb`: columns, indexes and foreign keys.

`db/schema.rb` is dumped from a development database, and a development database can carry columns from another branch's migrations that no migration on this branch creates. The test database loads `db/schema.rb`, so specs then run against a table production does not have, and code that reads the extra column passes its specs and fails in production. `legislator_votes.legislator_term_id` arrived this way.

The comparison reads the throwaway database before its folder is removed, so the migration chain still runs once. It covers `legislator_votes` only: `db/schema.rb` still declares other tables and columns that no migration creates, and those are outside this check.
