---
lat:
  mode: explanation
---

# Why term writing runs outside the hand-edit guard

`SeedLegislator#legislator` (`db/seeds/models/legislator.rb`) calls `SeedLegislatorTerms` whether or not `seed_or_skip?` just protected the row's person attributes.

The guard exists only to save a hand edit to first name, party, photo, and the other PERSON fields — no screen in Sway edits a `LegislatorTerm` row, so there is nothing for the guard to protect there.

## Why term writing must not sit behind the guard

Running term writing behind the guard would fail silently.

Any code that updates a `Legislator` row for an unrelated reason — a migration, a background job — moves `updated_at` without moving `last_seeded_at`, and `seed_or_skip?` reads that mismatch as a hand edit. The seeder would then quietly stop giving most members of Congress their terms, leaving a member with one `LegislatorTerm` row where the roster proves many.

The `SeedLegislatorTerms` call sits outside the guard, so terms are written on every run, guard or no guard.

`spec/db/seeds/congress_roster_spec.rb` reads the committed Congress roster file directly, because that file is the only thing that tells Sway how long each member really held each seat — everything downstream reads it: who is in office, and which term a vote belongs to. The roster is rewritten by `LegislatorsCache::BaseRefresh` every week, so a broken rewrite would quietly put the file back to one term per member with no seat named — a state that files votes under the wrong term. Reading the file itself means that state cannot recur without one of these examples going red.

## Executives get no term

An executive roster row gets no `Legislator` and no `LegislatorTerm`, except the curated President row, which is seeded like any other member.

[[official-service-evidence#The curated President record]] owns the rule that accepts that one row. Any un-evidenced sentinel terms created for other executives without official service evidence are retired during seeding as detailed in [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Presidential display]].

## Terms are inserted, never mutated in place

`legislator_terms` (`db/migrate/20260605000003`) is one row per `(legislator, term_start_year)`, and a row is never mutated once a later term exists for that legislator.

The seeder always INSERTs a new row on term advance rather than overwriting the prior one.

There is deliberately no completion-timestamp column and no boolean current-status flag on the table. "Current" is derived by date window at read time, through `TermWindow` and `LegislatorTerm.covering`/`.running_on` (`app/models/term_window.rb`). This dissolves the rollover-hook fragility the table replaced: the earlier `legislator_term_snapshots` design depended on a seeder callback that stamped a current-status column on term advance, which is exactly the kind of write-order dependency a date-derived read has no need for.
