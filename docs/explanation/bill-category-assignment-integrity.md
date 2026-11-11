---
mode: explanation
summary: "Explains why BillCategory validates uniqueness in Ruby on top of the database's unique index, and why Category::MAX_ACTIVE_PER_BILL is a single constant rather than four hand-typed limits."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Keeping a bill's category assignments consistent

## Why BillCategory validates uniqueness in Ruby, not only in the database

`BillCategory` validates `bill_id` uniqueness scoped to `category_id`, even
though `(bill_id, category_id)` also carries a database unique index.
Checking in Ruby means a duplicate `create!` raises
`ActiveRecord::RecordInvalid`, the exception the test suite asserts
against; a database-level violation alone would raise
`ActiveRecord::RecordNotUnique` instead, a different exception class from a
different layer. The database index still does real work: it is the
backstop for two `BillCategoryAssigner` runs racing each other, and for
re-running a backfill, cases where the Ruby-level check inside one process
can't see what another process just committed.

## Why MAX_ACTIVE_PER_BILL is one constant

`Category::MAX_ACTIVE_PER_BILL` (currently 3) used to be hand-typed
separately in four places: the assignment cap, the list-trim step, an
admin override, and a raw SQL guard. Nothing tied the four numbers
together, so they could drift without anyone noticing. It is now the one
source of truth all four read from.

A switched-off `bill_categories` link stays in the database rather than
being deleted, but it does not occupy one of a bill's three active slots —
so every place that counts toward the cap has to filter on
`categories.active = true`, not just count rows.

`category_max_active_per_bill_spec.rb`'s examples do NOT retest what each
place does — the existing specs for `BillCategoryAssigner`,
`Bills::CategoriesController`, and `Admin::CategoriesController` already
cover that. They pin the one thing no single spec can see: that all of
them enforce the SAME number (C2-IN-05).

## Why BillCategory's own spec enforces no cardinality limit

The "one to three categories per bill" rule is not enforced by the
`BillCategory` join model itself, which accepts any number of rows for a
bill. The ceiling of three is enforced by `BillCategoryAssigner#call` and
`Bills::CategoriesController#create`, and their own specs check it. The
floor is deliberately zero: a bill may finish with no category at all, and
a later job fills them in. `bill_category_spec.rb`'s "category cardinality
is enforced upstream, not by the join model" examples record that the
model imposes no limit of its own, so the limit further upstream is the
real rule — an earlier "allows 1, 2 or 3" example only showed those counts
were possible and never rejected 0 or 4, which read as more confidence
than it had earned.
