---
mode: explanation
summary: "Why Legislator.with_active_term's has_one :active_term preload is O(1) in query count but still scans every legislator_terms row per query, and why that isn't fixed here."
status: agent-extracted
related: []
---

# `Legislator.with_active_term` is query-count flat, not scan-flat

<!-- vale Vale.Spelling = NO -->

`Legislator.with_active_term` eager-loads `active_term`/`district` so the
number of SQL queries stays flat as the legislator count grows — no N+1.
But the *work inside* those queries does not stay flat.

## What the has_one scope actually does

`LegislatorTerm.current` — the scope block behind `has_one :active_term`
— runs `candidates = includes(district: :sway_locale).to_a` against every
`LegislatorTerm` row, because Rails has not yet added the legislator_id
filter that belongs to the association. It loads and sifts every term in
the database, however few legislators are in the current batch.

This was measured directly: a `has_one` scope block that takes no
argument never receives the owner's foreign-key filter up front, confirmed
by watching the raw SQL through `ActiveSupport::Notifications`.

## The alternative considered and rejected

Passing the owner into the scope (`->(legislator) { ... }`) would stop the
full scan. It was rejected because it would turn `.with_active_term`'s one
batched preload into one query per legislator — a worse trade for the busy
paths this scope serves.

## What a real fix would require

A real fix means doing `LegislatorTerm.current`'s date math in SQL, per
locale. Congress alone would be easy, since its sessions always convene on
January 3, but Maryland and Baltimore convene on the nth weekday of a
month, and copying that math outside `TermWindow` would break the
one-place-only rule this codebase keeps on purpose. This is tracked as
follow-up work, not yet done.

## Why the has_one declaration uses the qualified scope form

`Legislator#active_term` is declared as `has_one :active_term, ->
{ LegislatorTerm.current }, ...` — the qualified `LegislatorTerm.current`,
not a bare `current`. Rails merges the scope's WHERE clause with the
association's foreign-key condition either way, producing the same final
SQL. The qualified form is the one Steep can type-check: the vendored
ActiveRecord `has_one` RBS signature does not type the scope block's
`self` the way `has_many`'s does, so a bare `current` would not resolve
under Steep.

## Why .with_active_term preloads district directly, not nested

`Legislator.with_active_term` is `includes(district: :sway_locale)`,
preloading `district` directly rather than nesting it as `active_term:
{district: ...}`. This matters: Rails' `has_one`-through preloader loads
the intermediate `active_term` as part of the chain either way, but a
separate `active_term: {district: ...}` preload is not reused by
`#district` — that shape re-issues one query per record. Preloading
`:district` alone covers both `#district` and the `#title` delegate in a
fixed number of queries, no matter how many legislators load.

This scope is opt-in on purpose, not a `default_scope` — callers pay for
the eager load only on the hot paths that need it (for example, the
legislators index).
