---
lat:
  mode: explanation
---

# legislator factory: the transient district

`spec/factories/legislators.rb`'s `:legislator` factory keeps `district` inside a `transient do` block rather than declaring it as a normal association, and the reasons are easy to undo by "simplifying" the factory.

## district must stay transient

`Legislator` no longer has a `district_id` column — only a read-only `has_one :district, through: :active_term`.

FactoryBot auto-assigns, through `public_send`, every non-transient attribute that `initialize_with` does not name, and Rails does define a `district=` writer for a has_one-through association. Assigning through that writer quietly builds and saves a blank `active_term` (`LegislatorTerm`) to join the two, which then fails the NOT NULL check on `term_end_year`. Keeping it transient leaves `district` usable — by the `sway_locale { district.sway_locale }` line, and by a caller who overrides it — while never being auto-assigned.

`active` and `title` are transient too, and do nothing at all: both columns were dropped. Whether a legislator is serving is worked out entirely from their terms now (`Legislator#serving?`), and `title` lives on `legislator_terms`.

## Why the association names strategy: :create explicitly

`district { association :district, strategy: :create }` — the strategy is named on purpose, and this was measured rather than assumed.

This line used to read `create(:district)`, which always saves. Drop the strategy and `build(:legislator)` saves no district at all: `District.count` changes by 0 instead of 1. Twelve specs build a legislator, so a lint fix that quietly stopped writing that row would be a behaviour change, not a tidy-up.

It has to be written inside the `transient do` block, too. A bare `association :district` there would NOT be transient — `DefinitionProxy#association` ignores the transient flag, which is the auto-assignment problem described above. Only the inline `district { ... }` form (evaluated as a plain block) actually stays transient.

What does NOT justify the explicit strategy: the locale. `district.sway_locale` comes back already saved under either strategy, because the `sway_locale` factory hands out a seeded row (see [[docs/explanation/sway-locale-factory-design.md|sway_locale factory design]]). An earlier version of this comment claimed otherwise.

## Why external_id uses a plain sequence, not Faker::Color.color_name

`sequence(:external_id) { |n| "ext-#{n}" }` is unique by construction.

`Faker::Color.color_name` draws from a pool of about 72 values, which collides under the `(sway_locale_id, external_id)` unique index as soon as a spec creates several legislators in one locale.
