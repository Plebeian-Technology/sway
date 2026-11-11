---
mode: explanation
summary: "Why AdminSetting::SUPPORTED_MODELS dropped Sonnet 4.6 and Opus 4.8, and why its inclusion validations only check the column that changed."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why the AdminSetting model list changes the way it does

## Removing a model from the list

`AdminSetting::SUPPORTED_MODELS` is the only list of Claude models the admin
screens offer for `#summarization_model` and `#classification_model`. Sonnet
4.6 and Opus 4.8 were once on it. They still work, and they cost
the same as the models that replaced them — so an admin choosing one was
paying today's price for last year's answer, on every bill summary and every
testimony classification.

Removing them needed no data migration because production had never moved
off the default: both columns held `claude-haiku-5-5`, checked on
the live database first before the removal shipped.

Haiku 5.5 stays on the list because it is still the current Haiku, and
because it is the column default a fresh database starts from. To add a
model: update `SUPPORTED_MODELS`, add it to the `<select>` in the admin
screens, and if it matters, check the price and speed against the operator's
Anthropic billing console.

## Why the inclusion validations are conditional

Checking the live database first is not the only thing standing between a
future removal and a frozen settings row — the inclusion validations on
`#summarization_model` and `#classification_model` only run
`if: :<column>_changed?`.

Both columns hold a model name, and the list of names they may hold shrinks
from time to time (as it did in 2026-07). Rails runs every
validation on every save, so an unconditional inclusion check meant that one
stored name falling off the list froze the *whole* row: an admin editing the
other column was refused, with an error about a column they had not touched,
and the only way out was to edit the database by hand — nothing on the page
could clear it.

Checking only the column that changed keeps the guard where it does work — a
name arriving from a request is still refused unless it is on the list,
which is the whole point — while letting the operator pick a current model
and get out. A new record counts as changed on both columns, so a fresh row
is checked in full.

The stored name goes on working in the meantime: it is sent to Anthropic as
written, and a model taken off this list is one Sway no longer offers, not
one that has stopped answering. `Admin::LlmSettingsController` shows it in
the dropdown, marked and unpickable, so nobody has to guess what is running.

## Why the creating migration hardcodes the seed value

`db/migrate/20260528000001_create_admin_settings.rb` seeds the row's
`summarization_model` with the literal string `"claude-haiku-5-5"`,
not a reference to `AdminSetting::SUPPORTED_MODELS`. `SUPPORTED_MODELS`
changes over time, as the section above describes — a migration that read
through it would have its seed value retroactively rewritten by a future
edit to the constant, on any database that runs the migration after that
edit. The literal freezes what was actually migrated, independent of
whatever the constant holds by the time someone runs it.

## Why the retired-model tests write the column directly

Reproducing a stored-but-no-longer-offered model requires writing straight
to the column with `update_column`, bypassing validation — that is exactly
what "saved while the name was still allowed" leaves behind. Stubbing
`SUPPORTED_MODELS` does not work here: the inclusion validator reads the
constant once, at class load, so a stub never changes what it checks
against. The retired model these tests use, `claude-sonnet-4-6`, really was
on the list once, so the example describes a state
production has actually been able to reach, not an invented one.

## Why classification has its own column instead of reusing summarization

`Testimony::AttachmentClassifier` reads `#classification_model`, a separate
column from `#summarization_model`, on purpose. Classifying is a simple
judgment made in bulk over every candidate attachment, so sharing one
setting with summarization would mean that choosing a better (more
expensive) model for bill summaries silently raised the price of every
attachment classification too. Both columns draw from the same
`SUPPORTED_MODELS` list, but hold independent values.

## Why AdminSetting enforces its own one-row rule twice

`AdminSetting` is meant to hold exactly one row, ever. The creating
migration's `first_or_create!` (see below) means seeding never inserts a
duplicate, and `.singleton`'s own `first_or_create!` call means two
processes both calling it at application boot cannot both create a row.
Neither of those covers every caller, though — `AdminSetting.create!` in a
test, a one-off console session, or code written later could still insert
a second row directly. `validate :enforce_singleton` refuses any new
record while one already exists, so the one-row rule holds everywhere in
the app, not only through the paths that remembered to check first.

`.singleton` itself creates the row with the cheapest supported model
(`SUPPORTED_MODELS.first`, Haiku) if none exists, as a fallback for a row
deleted by hand — the ordinary path is the migration's seed, which runs
once when migrations run.

## Frontend: `ModelSelectField.tsx` and `supportedModel.ts`

`ModelSelectField.tsx` is shared by both LLM settings dropdowns so the aria
wiring (label, invalid, describedby) exists in one place, not two that
could drift apart.

`SupportedModel#selectable` (`supportedModel.ts`) is false when a model is
no longer on the allowed list but the row still holds it — shown so the
operator can see what's running, disabled because picking it would be
refused.

## Why the seed uses first_or_create!, not find_or_create_by!

Seeding a singleton row with `find_or_create_by!(summarization_model: ...)`
searches on the model VALUE, not on "is there already a row." Once an admin
has upgraded the singleton away from the seeded default, a later run of the
same migration (`db:prepare` on a fresh clone, `db:migrate:redo`, and
similar) would search for a row matching the seed value, find none, and
insert a SECOND row — breaking the singleton. `first_or_create!` with no
condition searches for the first row of any shape, returns it unchanged if
one exists, and only inserts the default attributes on a truly empty table.
