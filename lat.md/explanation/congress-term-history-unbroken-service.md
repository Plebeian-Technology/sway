---
lat:
  mode: explanation
---

# congress.gov terms.item: unbroken service, not one term

`SeedPreparers::Legislators::CongressDotGov#term_from` turns one `terms.item` entry into the term row it stands for.

An entry is a stretch of UNBROKEN SERVICE in one chamber, not a single term: `startYear` is the year the member first took that seat, and a missing `endYear` means they hold it still.

## The fixed-length-term bug

Reading `startYear` as the start of a fixed-length term hands a senator who has served since 2013 a term that finished in 2019. Now that a term's end decides who is in office, that reads as out of office.

## The fix

A stretch that is still open reports the term running to TODAY, counted off the real first year; a stretch that has closed reports the years it recorded.

## Seat naming

An entry can also name the seat it was served in, as `"stateCode"` and `"district"`.

Only the fuller history written by `CongressTermHistory` carries those two keys — congress.gov's own roster does not. When they are absent, the district comes back `nil` and the seeder falls back to the member's current seat, which is what it always did.

## Picking the current term: max_by, not position

`#current_term` and `#term_start_year` both pick the current (newest) term by `startYear`, using `max_by` rather than position.

`#current_term` and `#term_start_year` both pick the current (newest) term by `startYear`, using `max_by` rather than position: `terms.item` is NEWEST-first for POTUS (`[2025, 2021]`) but oldest-first for senators and representatives — a positional `.last` would read POTUS's old 2021 term. `max_by` finds the current term for both orderings. When the blob has no `terms.item` at all (a thin blob for a genuinely new member), `#term_start_year` falls back to the current odd year, since Congresses convene in odd years.

## authoritative_term?

True only when the blob carried a real `startYear` in its NEWEST `terms.item` — which holds for all 540 committed Congress entries (verified).

False for a thin blob (a new member with no `terms.item`): the fallback odd-year is tagged non-authoritative, and `#proven_terms` never reports it.
