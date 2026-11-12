# Migrations name no model

A migration never changes again; a model changes every week. A migration that calls a model class depends on code written months after it, and that dependency has already broken two deploys.

`spec/migrations/migrate_from_empty_spec.rb` builds the database from nothing on
every run, so the day a model grows a field backed by a later column, the suite
goes red and names the migration. The stand-in classes below remove the exposure
rather than waiting to be told about it.

## Stand-in classes

A stand-in is a bare `ActiveRecord::Base` subclass, defined inside the migration
that uses it, that knows the table name and nothing else — no validations, no
callbacks, no default scope, no enum.

`db/migrate/20260420000001_normalize_user_phones.rb` holds the original of the
pattern. Where a migration needs more than plain table access, the stand-in
carries only what that migration asks of it: the association it traverses, or
the one predicate it dispatches on. `20260429000001` needs a locale's
`congress?` and `regional?`, and re-derives both from `RegionUtil` rather than
from `SwayLocale`, because those two predicates are the whole reason that
backfill cannot be written in SQL.

Inheriting `ApplicationRecord` defeats the point: it is an application class
that can gain behaviour at any time, so a stand-in inherits `ActiveRecord::Base`
directly.

## Why a stand-in re-reads its columns

A class caches its table's columns the first time it is asked, and a migration file is loaded before the migrations that run ahead of it in the same deploy have added theirs, so a stand-in can hold a column list that is already out of date.

`db/data/20260711000004_convert_duplicate_legislators_to_terms.rb` is where that
bites: it runs after the schema migrations that add `legislators.sway_locale_id`
and recreate `user_districts` in the same deploy, and it writes both. Calling
`reset_column_information` on every stand-in at the top of `#up` re-reads the
columns from the live, mid-chain schema before anything is written.

It is not an alternative to a stand-in, as it once was when these migrations
named models — it is what a stand-in needs in order to be safe in the middle of
a chain.

## The calculators a stand-in cannot replace

Nine data migrations still name a class `app/models` defines, and `MigrationModelCheck::ALLOWED_REFERENCES` records each one by file and by constant. None of them is table access.

`TermWindow` is a calculator over plain objects: one migration hands it a
`Struct`, not a record. `Address.normalized_key_for` is a calculator over
coordinates and units. `SwayLocale::TermRulesRegistry` and
`SwayLocale::JurisdictionRulesRegistry` hold the real convening dates and roster
rules of real jurisdictions. `CongressChamber` says how long a senator's term
runs, and `LegislatorIdentity` is the value object that decides what identifies
a person. A copy of any of them inside a migration would be a second statement
of Baltimore's, Congress's, or Sway's own rules, free to disagree with the first with
nothing to notice, which is a worse outcome than the coupling it would remove.

`BillLlmProvisioning` is the one exception that is a model rather than a
calculator. The retirement sweep writes that model's own evidence-retraction
mark, and the mark's format has to be stated once; the same migration reads its
rows through a stand-in, so only the two mark helpers reach the model.

The user-district backfill is where the difference shows. It used to traverse
`Legislator#active_term`, a model association whose scope reaches request-scoped
state; it now asks `TermWindow.running_on` which of the terms the migration
itself just created is running today, which is the same question the
association answers, asked of the same calculator. The two Baltimore seat
merges ask it the same way.

## What a rehearsal against production data checks

A migration chain rehearsed against a copy of the real database is judged on what happened to the people in it, not on whether the chain ran.

Two questions carry that. Nobody disappears: the chain merges rows and one
correction deletes the empty row a city holds beside each seat, so the row count
is expected to fall while every distinct person in every locale still has a row
afterwards. And no identifier is invented: the only keys retired are the ones
the correction deliberately retires, when the empty seat-named row's name is
handed to the row holding that person's votes. A snapshot taken after the
correction has already run retires none at all, which is the shape that makes
the check safe to repeat.

## A uniqueness validation is not a constraint

A model-level uniqueness validation checks by reading before it writes, so two
requests can both read nothing and both insert.

Where a table is genuinely one-row-per-key, the index is made unique to say so
in the place that cannot race. The score tables are the clearest case: their
rows are created through find-or-create and after-commit defaults, so a race
inserts duplicates, and their sibling locale-scores table already carried a
unique index. The same reasoning covers a curated category name, and a
passkey's label within one account, where the display list is the thing a
duplicate spoils. A unique index also enables an upsert, which a non-unique one
cannot.

An index added for reading rather than for uniqueness is left non-unique on
purpose. A legislator's external id is probed once per roll-call vote during
ingestion, which is what the index is for; two locales can legitimately publish
the same identifier string, so uniqueness there would be wrong, and a composite
unique index was held back until a planned identifier rewrite had run rather
than risk tripping it midway.

## A column nothing writes is dropped in its own change

Removing the last reader of a column and dropping the column are two different
risks, so they are two different changes.

A dead read can be removed and reverted freely; a dropped column takes its data
with it. Splitting them means the second change starts from a state where
nothing has read the column for a release. The same applies to a column written
but never read: it is deleted rather than left, because an unused column is the
one a future reader reaches for by accident.

Where a column's nullability disagrees with the model's own required
association, the migration aligns the column and refuses loudly on a row that
should not exist, rather than coercing it — a row the model could not have
created is bad data, and an operator should see it before the deploy continues.

## The gate

`bundle exec rake sway:lint:migration_models` fails when a file under
`db/migrate` or `db/data` names a constant `app/models` defines and the
migration does not define itself.

`lib/migration_model_check.rb` parses with Prism rather than searching text, so
a name inside a comment or a string is not a finding. It reads a qualified
reference whole — `SwayLocale::TermRulesRegistry` is one name, not two — and it
exempts a constant the migration defines in its own body, which is what lets a
migration define a stand-in under the model's own name.

Its file list comes from `Dir.glob` rather than from `git ls-files`, unlike
`lib/env_read_check.rb`: an untracked migration is a file about to be committed,
and a check that skipped it would pass on exactly the change it exists to catch.

## Every migration in the tree passes

`MigrationModelCheck` reports no offence across all 179 migrations, so the gate is a rule the repository actually keeps rather than a target it is working towards.

Nine data migrations written in July and August 2026 were converted together in
one pass, each keeping its own spec green — the legislator and term
conversions, the two Baltimore seat merges, the identifier backfill and the
draft-position retirement. There is no grandfathered list, and the check
refuses to run at all when a path in `ALLOWED_REFERENCES` no longer exists, so
a rename cannot quietly retire an entry.
