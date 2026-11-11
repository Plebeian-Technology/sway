---
mode: explanation
summary: "Why spec/migrations/add_source_to_legislator_votes_spec.rb cleans up its sway_locale fixtures after every example rather than relying on before/after(:all) hooks, and the order-dependent leak that made the gap invisible."
status: agent-extracted
related: []
---

# Why this migration spec cleans up after every example

`spec/migrations/add_source_to_legislator_votes_spec.rb` tests the Ruby
code inside a migration that fills a new column with a different value per
locale. The migration has already run against the test database, so the
examples roll it back and run it forward again, inside an example with
transactions turned off (`self.use_transactional_tests = false`), to make
that fill-in code actually execute. SQLite commits schema changes such as
`add_column` and `change_column_null` immediately, and no transaction can
undo them.

## The order-dependent leak this guards against

Transactions are off for this whole describe block, so nothing any example
creates is rolled back — and the only clean-up used to live in the
"backfill" group's `before(:all)`/`after(:all)` hooks. Running in file
order, the sanity-check group happens to go first, and that
`before(:all)` tidies up after it, which is why this looked clean. In any
order that runs "backfill" FIRST, the three locales the sanity checks
create outlive the run and stay in `storage/test.sqlite3` for every later
run against that database.

This was reproduced, and it is repeatable for a given random seed: this
file on its own under `--order rand:37` left 3 `sway_locales` behind, both
times it was tried, while `--order rand:3` and `--order rand:13` left
none. The factory looks a locale up by `(city, state, country)` and
creates one only if it is missing, so the mess stays invisible until
something asks how many locales exist or which one it got — the worst kind
of leftover, not a harmless one.

## Why cleanup runs after every example instead

`after { cleanup_test_locales }`, for the whole file, is what makes this
file independent of order by design rather than by which group RSpec
happens to schedule first. It also covers the backfill example, whose
records the helper already knows how to remove.
