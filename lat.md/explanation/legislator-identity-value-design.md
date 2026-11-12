---
lat:
  mode: explanation
---

# LegislatorIdentity and LegislatorIdentifier design

`LegislatorIdentity` is what one roster source calls one person, in one locale: a source name and a value. It is stored as a `LegislatorIdentifier` row, and is the only thing the seeder is allowed to decide "same person" by.

## Why a value, and not just the published id

Most sources publish an id for the PERSON, and that id is the whole identity — a bioguide id, an OpenStates ocd-person id.

Baltimore's does not: Open Baltimore republishes one record per SEAT, so `"baltimore-district-1"` names the office and whoever fills it. A seat alone cannot identify a person, and when a council member leaves, the successor arrives under the same key. Reading that as the same person writes the successor's name onto the row holding the departed member's votes.

Adding the published NAME to the seat makes the pair identify a person. This is not the same as matching on a name: a name MATCH asks "are these two people the same?", and answering yes wrongly MERGES two records — one person's votes silently become another's. A verified counter-example: bioguide `M000639` (Robert Menendez, Senator, b. 1954) and `M001226` (his son, Rep. NJ-8, b. 1985) are the same name in the same locale.

## Why the failure mode runs the other way

The name is part of the KEY here, not a match rule, so the failure runs the other way: a name that arrives spelled differently produces a value nothing matches, which creates a DUPLICATE person.

That is visible on the legislators page, caught by `spec/production_readiness/production_legislator_identity_spec.rb`, and mended by adding an identifier row that points the old value at the kept person. Losing a record is not recoverable; showing one twice is — so the design accepts the recoverable failure.

## Why seat_and_name returns nil on a blank published name

`LegislatorIdentity.seat_and_name` returns `nil` when the source published no usable name under the seat.

An entry with no name cannot say which person holds the seat, so the caller skips it and leaves the person already on that seat exactly as they are. Seeding it instead would write the blank over their name. The deleted Baltimore refresher produced such entries: it wrote a blank name when Legistar could not say who chaired the council.

## Why a seat may not contain the separator

`seat_and_name` raises if the seat half contains `SEPARATOR` (`"|"`).

`#name_key` already strips the separator out of the name half; a seat carrying one would make the two halves impossible to tell apart when `#seat_from` later needs to split them.

## Why seat_from exists as its own method

`LegislatorIdentity.seat_from` returns the seat half of a seat-and-name value, or `nil` when there is none.

It lets a caller ask "is this row sitting in a seat the roster named?" without treating the seat as an identity — a seat says which office, never which person.

## Why name_key folds accents before collapsing punctuation

`LegislatorIdentity.name_key` reduces a name to the part a re-publish is unlikely to change: lower case, accents folded away, everything that is not a letter or digit collapsed to a single dash.

The two steps run in this order for a reason: Unicode NFKD normalization splits an accented letter into the letter and a separate combining mark, and the mark is not a letter, so collapsing punctuation before dropping the marks would turn "Núñez" into "nu-n-ez" — one dash per accent, and a name whose key changes the moment the source publishes it unaccented. Dropping the marks first folds it to "nunez", which is the point of decomposing at all.

## Why LegislatorIdentifier's many-to-one shape is the point

`LegislatorIdentifier` records what a source calls a person, so the seeder never has to work it out again: one row per `(locale, source, value)`, many rows may point at the same person.

The many-to-one is deliberate — a person who changes seat gets a second value under a seat-keyed source (a council member moving from a district seat to Council President, for example), and both values name the same human being. With the identity held in a single column on `legislators` there was nowhere to say so, and the second value would have created a second person. Re-keying is now a row somebody adds deliberately, in a migration, and the mapping is kept afterwards.

The seeder only ever READS this table to find a person and WRITES the value it just built. It never infers a mapping — matching on name alone is the one thing that must not happen (see above).

## What production_legislator_identifiers_spec.rb checks

`spec/production_readiness/production_legislator_identifiers_spec.rb` reads what the identifier backfill actually did to the real data, after the whole migration chain has run.

A data migration reports itself through `say`, which goes into the deploy log and is read by nobody; these counts are read by the build instead.

"records one identifier per legislator the roster can name, under that locale's own scheme" is measured after the WHOLE chain, which is the backfill followed by the Baltimore join (see [[docs/explanation/production-baltimore-one-person-verification.md|production-baltimore-one-person-verification.md]]). The primary roster schemes account for the bulk of the identifier rows; the Baltimore `curated_person` rows are the names the joined-away rows went by, kept so the mapping is not thrown away; Annapolis adds a few more `curated_person` rows. The undeclared locales hold no legislators and so appear nowhere in the count.

## What production_legislator_identity_spec.rb checks

`spec/production_readiness/production_legislator_identity_spec.rb` checks one person, one row in office — against real production data, after the whole migration chain has run.

It exists because the cleanup that is supposed to deliver it (the data migration `20260801000001`) can run on production and merge none of its seats without anyone noticing: a data migration reports what it did through `say`, which goes into the deploy log and is read by nobody. The counts in this spec are read by the build instead.

The second example is the one a reader would have reported first: Baltimore's duplicate rows were both linked to the same accounts, so each affected representative was listed twice on `/legislators`.

The spec expects no duplicate people and no duplicate listings.

## Why locale_matches_the_legislator is a validation, not a correction

`LegislatorIdentifier#locale_matches_the_legislator` refuses a row whose `sway_locale_id` disagrees with its `legislator`'s own locale, rather than silently correcting it to match.

Carrying `sway_locale_id` directly on `LegislatorIdentifier`, rather than reading it through the legislator, is what lets the unique index scope a value to one jurisdiction without a join — Baltimore's `"district-1"` and another city's must never collide as one row. The two can only disagree by a programming error, which is why the validation refuses rather than silently fixing the mismatch.
