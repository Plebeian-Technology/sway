---
mode: explanation
summary: "Why spec helpers use named top-level classes and module methods instead of `let`, `Class.new` blocks, and `Struct.new` blocks."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why spec helpers avoid `let`, `Class.new`, and `Struct.new` blocks

Steep, the type checker this repo runs (`bin/steep check`), cannot resolve
several shapes RSpec examples reach for by default. Specs that need a typed
test double use one of three replacements instead, all for the same
underlying reason: each broken shape hides a definition inside a block whose
receiver Steep does not track back to where the code actually runs.

## `let` and `def` inside a `describe` block

Steep resolves neither a `let` helper nor a `def` written inside a
`describe`/`context` block — a call to either reports something like `Type
::Object does not have method ...` even though the helper works fine at
runtime. The fix is to declare the helper outside `RSpec.describe`
entirely: a module holding plain class methods (`def self.foo`) and
constants. `spec/lib/sway/settings_spec.rb` and
`spec/lib/sway/subprocess_spec.rb` both do this, each in a top-level
module (`SettingsSpecHelpers`, `SubprocessSpecHelpers`) sitting above the
`RSpec.describe` block.

### Accepting the gap with `steep:ignore` instead of moving the helper out

`spec/requests/bills_deferred_reload_spec.rb`'s `bill_titles` helper stays
a `def` inside the example group, wrapped in `# steep:ignore:start` /
`# steep:ignore:end`, rather than moving out to a top-level module. At
runtime RSpec binds it to the example group and it works fine — this is a
gap in the type model, not a real error, and the repo silences such cases
the same way elsewhere rather than always restructuring around it.

## `Class.new(SomeBase) do ... end`

A block passed to `Class.new` types its own `self` as plain `::Class`, so a
macro call inside the block — `attr_config`, `coerce_types`, and similar
class-body DSL calls — does not resolve; Steep has no way to know the block
executes in the context of the anonymous subclass. A **named** top-level
class with an ordinary class body does not have this problem: `class Foo <
Bar; attr_config ...; end` is regular Ruby class-body execution, resolved
exactly the same way a real production class is. `settings_spec.rb`'s three
deliberately-broken probe classes (`NoTypeProbe`, `WrongPrefixProbe`,
`MissingRequiredProbe`, `IntegerProbe`, `FloatProbe`) are all named classes
for this reason, not `Class.new(Sway::Settings::Base) do ... end` blocks.

Named top-level classes carry one more benefit here: none of them are
defined inside a `describe`/`it` block, so RuboCop's
`Lint/ConstantDefinitionInBlock` — which flagged an earlier draft of this
pattern — never applies.

## `Struct.new(:x) do ... end`

The same problem shows up in a different shape with `Struct.new`. A method
defined inside a `Struct.new(...) do ... end` block is attributed by Steep
to the class *surrounding* that block, not to the anonymous `Struct`
subclass itself — so an instance method like `#join` cannot be typed where
it actually lives, and a call to it reports an unresolved method. Test
doubles that need instance methods (`SubprocessSpecHelpers::UnreapableWaiter`,
`SettingsSpecHelpers::SettingsSetterVisitor::SettingsWrite`) are written as
plain, ordinary classes instead — `attr_reader` plus a hand-written
`initialize` — even where a `Struct.new` would otherwise be the shorter
way to write the same thing.

## Why `spec/jobs/backup_database_job_spec.rb` writes its `instance_double` stub inside each example, not in a `let`

`BackupDatabaseJob` catches `DatabaseBackupService` errors so a failure is
logged rather than raised. Its spec covers only the job's
error-catching behavior — `DatabaseBackupService`'s own spec covers how a
backup actually works, so the service is stubbed here rather than exercised.
The `instance_double` is built inline inside each `it` block instead of a
shared `let`, following the same "Steep does not resolve a `let` back to
where the code actually runs" pattern described above.

## Why pending_org_digest_entry_spec.rb's helper is named build_pending_entry, not build_entry

Spec helper type signatures declared for `def`-in-`describe` helpers are
declared once, globally, in `sig-test/spec_globals.rbs` (the same file
referenced throughout this document) — Steep resolves them by name alone,
with no per-file scoping. `pipeline_activity_log_entry_spec.rb` already
declares a `build_entry` helper that takes keyword arguments only, so
`pending_org_digest_entry_spec.rb` cannot reuse that name for a helper
with a different shape (`build_pending_entry(user, **overrides)` takes a
positional argument): one name cannot carry two different signatures in
one global declaration file.

## Why `category_spec.rb`'s EXPECTED_CATEGORY_NAMES sits outside the describe block

A constant assigned inside a `describe`/`it` `do...end` block lands on
`::Object` anyway — the same problem `let` and `def` have for Steep,
described above — and RuboCop's `Lint/ConstantDefinitionInBlock` points
that out. Defining `EXPECTED_CATEGORY_NAMES` at the top level of
`category_spec.rb`, outside `RSpec.describe`, says plainly where it
actually lands rather than hiding that behind block scoping.
`sig-test/spec_globals.rbs` declares its type.

## Why `spec/jobs/on_user_email_saved_send_email_to_legislator_job_spec.rb` repeats its setup instead of a `def` helper

The "when delivery raises" examples in this file repeat the same
setup (locale, legislator, bill, `UserLegislatorEmail`) inside each `it`
rather than pulling it into a `def` helper at the example-group level — a
`def` written there lands on `::Object`, the same unresolved-definition
problem `let` has for Steep (see above), and the type checker objects to
it.
