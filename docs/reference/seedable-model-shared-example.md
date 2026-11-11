---
mode: reference
summary: "How to use the 'a seedable model' RSpec shared example: parameters and the three skip-guard cases it covers."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# The "a seedable model" shared example

`spec/support/shared_examples/seedable.rb` covers the three standard cases
where a seeder has to decide whether to leave a record alone. Used from each
seeder spec:

```ruby
include_examples "a seedable model",
  model_class: Legislator,
  factory_name: :legislator,
  natural_key_attrs: { external_id: "abc", first_name: "X", last_name: "Y" },
  run_seeder: ->(force:) { SeedLegislator.run(sway_locales, force: force) }
```

`model_class:` is required. Inside the shared example, `described_class` is
the SEEDER class (`SeedSwayLocale`, for example), which has no `find_by`.
The ActiveRecord model class is passed in explicitly so the "seeded a new
record" assertion can always look the row up with
`model_class.find_by(natural_key_attrs)`.

The factory must build a record whose `natural_key_attrs` match what the
seeder writes. Otherwise the seeder's `find_or_initialize_by` creates a NEW
record rather than updating the one the factory built, and the assertions
never fire.

The example checks three cases:

1. Seeding a new record stamps `last_seeded_at == updated_at`.
2. A record whose `updated_at != last_seeded_at` (edited out-of-band) is
   skipped on a normal (`force: false`) run.
3. `force: true` re-seeds and re-stamps even a record edited out-of-band.
