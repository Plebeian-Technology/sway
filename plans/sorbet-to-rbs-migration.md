# Plan: Migrate from Sorbet to RBS

## Objective

Remove Sorbet entirely while preserving existing runtime behavior and keeping test coverage intact. Type information moves to RBS in `.rbs` files, migrated piecemeal with validation after each batch.

## Ground Rules

- Change types only; do not change method behavior or business logic.
- Runtime checks added for Sorbet are not preserved; Sorbet runtime handling is removed.
- Migrate in batches and run `dip run rspec` between batches.
- Keep this as one PR.
- Keep `syntax_tree-rbs` in `Gemfile`.
- Do not expand scope to additional Sorbet-adjacent cleanup beyond what is listed.

## Scope Snapshot

- **96 files** have `extend T::Sig`
- **~280 sig blocks** across ~47 files
- **78 `T.cast`**, **15 `T.let`**, **50+ `T.nilable`** usages
- **4 files** with `T::Configuration` handlers
- **397 RBI files** in `sorbet/` to delete
- **4 gems** to remove (`sorbet-runtime`, `sorbet`, `tapioca`, `rspec-sorbet`)

## Implementation Phases

### Phase 1: Remove Sorbet runtime/config hooks

1. **Delete** `config/initializers/sorbet.rb`.
2. **Remove** `T::Configuration.inline_type_error_handler` lines from:
    - `app/controllers/application_controller.rb`
    - `app/models/sway_locale.rb`
    - `app/controllers/sway_registration_controller.rb`
3. **Remove** `require "rspec/sorbet"` from `spec/rails_helper.rb`.
4. Run `dip run rspec`.

### Phase 2: Remove Sorbet syntax from Ruby (batch-by-batch)

Apply transformations in order; run `dip run rspec` after each batch:

1. Remove `# typed: strict|true|false` comments where not needed.
2. Remove all `extend T::Sig` lines.
3. Remove `extend T::Helpers` and `interface!` from:
    - `app/models/concerns/supportable.rb`
    - `app/models/concerns/agreeable.rb`
      Also remove abstract `sig` blocks while preserving method stubs/shape.
4. Remove all `sig { ... }` and `sig do ... end` blocks.
5. Remove `T.cast(super, ClassName)` association-wrapper overrides by deleting those wrapper methods only.
6. Replace `T.cast(self, ModuleName)` usage in concerns with direct `self` calls.
7. Replace remaining `T.cast(expr, Type)` with `expr`.
8. Replace `T.let(value, Type)` with `value`.
9. Handle `bill.rb` special case:

```ruby
# Before
T.cast(super.nil? || super, T::Boolean)
# After
super.nil? || super
```

### Phase 3: Remove Sorbet gems/infrastructure

1. In `Gemfile`, remove:
    - `gem "sorbet-runtime"`
    - `gem "rspec-sorbet"`
    - `gem "tapioca", "~> 0.17", require: false`
    - `gem "sorbet"`
    - comments tied to these entries
2. Keep `gem "syntax_tree-rbs"` unchanged.
3. Delete the entire `sorbet/` directory.
4. Run `bundle install` to regenerate `Gemfile.lock`.
5. Run `dip run rspec`.

### Phase 4: Generate and refine RBS piecemeal

1. Initialize/install collection:

```bash
rbs collection init
rbs collection install
```

2. Commit only:
    - `rbs_collection.yaml`
    - `rbs_collection.lock.yaml`
      Do not commit downloaded collection cache/vendor directories.
3. Create `sig/` structure mirroring `app/` areas being migrated.
4. Use `rbs prototype` for initial generation, then refine by hand.
5. Use `rbs collection` type definitions plus handwritten signatures for Rails/app code.
6. Migrate highest-signal files first, then continue in batches:
    - `app/models/sway_locale.rb`
    - `app/services/score_updater_service.rb`
    - `app/models/user.rb`
    - `app/models/bill.rb`
    - `app/controllers/application_controller.rb`
7. Run `rbs validate` and `dip run rspec` between migration batches.

### Phase 5: Type-checking and CI

1. Add RBS type-checking in CI (`steep check`).
2. Keep `rbs validate` as a syntax gate.
3. Ensure CI remains green with full test + type gates.

## Verification Checklist

- `dip run rspec` passes (full suite).
- `rbs validate` passes.
- `steep check` passes (local and CI).
- No remaining Sorbet DSL/usages in app code:
    - `extend T::Sig`
    - `sig` blocks
    - `T.cast` / `T.let`
    - `T::Configuration`
    - unnecessary `# typed:` comments
- `Gemfile`/`Gemfile.lock` no longer include the 4 removed Sorbet gems.
- `sorbet/` directory is deleted.
- Behavior-preservation spot checks: no method logic changes beyond type construct removal.

## Key Files Expected to Change

| File/Path                                   | Change                                                            |
| ------------------------------------------- | ----------------------------------------------------------------- |
| `config/initializers/sorbet.rb`             | Delete                                                            |
| `app/controllers/application_controller.rb` | Remove Sorbet DSL + runtime handler                               |
| `app/models/sway_locale.rb`                 | Remove Sorbet DSL + runtime handler + casts/lets                  |
| `app/services/score_updater_service.rb`     | Remove Sorbet DSL + casts/lets                                    |
| `app/models/concerns/scoreable.rb`          | Remove Sorbet DSL + `T.cast(self, ...)` replacements              |
| `app/models/concerns/supportable.rb`        | Remove `T::Helpers`/`interface!`/abstract sigs, keep method stubs |
| `app/models/concerns/agreeable.rb`          | Remove `T::Helpers`/`interface!`/abstract sigs, keep method stubs |
| `Gemfile`                                   | Remove 4 Sorbet-related gems                                      |
| `Gemfile.lock`                              | Regenerated without removed gems                                  |
| `spec/rails_helper.rb`                      | Remove `rspec/sorbet` require                                     |
| `sorbet/`                                   | Delete entire directory                                           |
| `sig/**/*.rbs`                              | Add piecemeal RBS definitions                                     |
| `rbs_collection.yaml`                       | Add/commit                                                        |
| `rbs_collection.lock.yaml`                  | Add/commit                                                        |
