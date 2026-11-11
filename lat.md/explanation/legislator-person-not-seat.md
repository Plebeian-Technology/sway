---
lat:
  mode: explanation
---

# Legislator models a person, not a seat

A `Legislator` row is a PERSON, not a seat.

The table once carried seat columns — `district_id`, `active`, `title` — that were transitional, and the model never reads them today. Every seat-tenure fact (district, title) resolves through the date-derived `active_term` (a `LegislatorTerm` row) instead.

`scope :serving` (`joins(:active_term)`) and the score associations both follow from this. `serving` replaces both of the dropped `active` and `in_office` flags: a person with no term covering today is not "serving," and there is no separate person-level flag to keep in sync with the roster. Score rows (`legislator_district_scores`, `legislator_locale_scores`) are keyed by term, not by legislator — the transitional `legislator_id` column and its `has_one` associations were dropped — so reading a legislator's current score means reading the ACTIVE TERM's rows via `#current_district_score`/`#current_locale_score`, not a column on `Legislator` itself.

## Why District reaches its legislators through terms, not directly

Legislators are not linked straight to a `District`.

Which seat a legislator held, and when, lives in `legislator_terms`, and that is the table holding `district_id` — so a district reaches its legislators through terms (`District#legislator_terms`), the same reason `Legislator` resolves district and title through `active_term` rather than through its own columns.

## Why LegislatorDistrictScore is keyed by district at all

A `LegislatorDistrictScore` row scoring "a legislator within one district" can look redundant, since a legislator maps one-to-one to a district through their active term.

It is not: when a legislator changes districts — through redistricting, or election to a new position — the district on the score row is what tells the new district's scores apart from the old district's, rather than blending them together under one legislator-level total.

## external_id means different things per source

`external_id` is the one value that identifies a `Legislator` row to its upstream source, which is what its unique index (`sway_locale_id`, `external_id`) says. What it identifies depends on how that source publishes ids:

- A source that publishes one id per **person** — that id is `external_id`
  directly.
- A source that publishes one id per **seat** — `external_id` is the seat id
  and the published name together, so two people who have occupied the same
  seat over time are two separate `Legislator` rows.

Which shape a given locale uses is declared, not guessed: `SwayLocale::TermRules#identified_by`, read through `LegislatorIdentity`.

`SeedPreparers::Legislators::Base#identity` is what the seeder may decide "same person" by, and is nil when the entry carries nothing that identifies a person — which the seeder reads as "skip this row" rather than as a new person. Every source has to answer for itself, because the shape differs: a person-level id for most, and a seat plus the published name for a roster keyed by office. There is no default arm on purpose — a source added later that quietly inherited the wrong shape is the whole family of defect this replaces.

`SeedPreparers::Legislators::Sway#identity` is the concrete case: a curated roster can be keyed either way, so the LOCALE says which — `SwayLocale::TermRules#identified_by`. This preparer reads whatever file Sway maintains for a locale, and the two cities Sway might add next could publish either shape, so reading the declaration is what stops the second one inheriting Baltimore's answer without saying so. There is no final `else` in its `case` statement: a value nobody has taught this method about refuses rather than falling through to whichever arm happens to be last.

## Why a spec fixture's locale must match the seeder's run locale

A `Legislator` row is identified by locale plus `external_id` together (the unique index above), not by `external_id` alone.

So a `Legislator` built by a factory in a spec has to sit in the SAME `SwayLocale` the seeder runs against in that example, or the seeder treats the fixture as a different person entirely and seeds a duplicate rather than finding the existing row. `seed_legislator_spec.rb`'s "skip guard" examples write this case out explicitly rather than reusing a shared example, since the guard's whole point — leaving a hand-edited row alone — only holds when the seeder actually recognizes the row as the one it already seeded.

## No default_scope

`Legislator` carries no `default_scope`. Callers opt in to eager loading the active term (and, through it, district and locale) via `.with_active_term` rather than paying for it on every load.

## The seat-collision bug

`SeedLegislator#person_for` (`db/seeds/models/legislator.rb`) used to be `Legislator.find_or_initialize_by(sway_locale:, external_id:)`.

For a roster keyed by SEAT, that reads a successor as the previous occupant: the Baltimore ArcGIS layer republishes `"baltimore-district-1"` with the new member's name, the finder returns the row holding the departed member's votes, reader links, and score history, and the caller writes the successor's name onto it — nothing compared the incoming name to the stored one, and `seed_or_skip?` only asks whether a human edited the row, not whether the row is even the right person.

The fix looks the person up in `LegislatorIdentifier` first. Asking the identifier table, a successor matches nothing and becomes a new person; the departed member keeps their own record.

## Why LegislatorLocaleScore exists separately from LegislatorDistrictScore

`LegislatorLocaleScore` is a locale-wide tally of how much users agree with a legislator, distinct from `LegislatorDistrictScore`.

`LegislatorLocaleScore` is a locale-wide tally of how much users agree with a legislator, distinct from `LegislatorDistrictScore`: it counts ALL users in the legislator's `SwayLocale` (their jurisdiction) who voted on the relevant bill, no matter which district they live in, rather than only the users in the legislator's own district. It powers the "\[locale] agreement with \[name]" chart on `LegislatorDetailScreen`. Like `LegislatorDistrictScore`, rows are keyed by `legislator_term_id`, not by legislator, for the same reason described above.

## Why a legislator can hold more than one identifier row

`Legislator#legislator_identifiers` (`has_many ..., dependent: :destroy`) records what each upstream source calls this person.

More than one row is normal, and is the point: a person who changes seat picks up a second identifier value under a seat-keyed source and stays the same `Legislator` row, rather than becoming a new person because their seat-derived id changed.

## Why the identifier lookup isn't belt-and-braces

`person_for` still falls back to `find_or_initialize_by` when the identifier lookup misses.

That second arm is not redundant: `external_id` holds the same value as the identity under a UNIQUE index, so a row already carrying it IS this identity — and without this fallback, a row whose `LegislatorIdentifier` is missing (a locale added after the identifier backfill, or a row written by a migration outside the seeder) would be read as a new person, and the INSERT would break the UNIQUE index and take the whole seed down. `db:seed` runs on every container boot, so that is a boot failure on the Pi. Finding the row here heals it instead — `LegislatorIdentifier.record!` writes the identifier a moment later.
