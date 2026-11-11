---
lat:
  mode: explanation
---

# TermWindow design notes

`TermWindow` works out when a term of office runs, for any locale.

It is a plain Ruby object with no database behind it, so `LegislatorTerm`, `ScoreRecomputeService`, and the seeder all ask the same questions here instead of duplicating date math.

The rules themselves live in `SwayLocale::TermRulesRegistry`, one per locale, beside the law each comes from — not in `TermWindow` itself. This class used to hold all locales' rules and pick between them by locale kind, the same defect described in [[docs/explanation/term-rules-design.md|term-rules-design.md]]: a new locale with no entry silently inherited Baltimore's rules. A locale with no declaration now refuses instead of borrowing one.

## Why begins_on falls back to the convening date

`#begins_on(term)` returns the real day recorded on the term, or failing that, the locale's handover day. A term is stored as two YEARS, so nothing else can say somebody arrived mid-cycle.

## Why covering checks starts alone

`#covering(vote_date, candidate_terms)` checks only whether a term began on or before `vote_date`; it has no end to read for the year-only candidates a data migration feeds it.

`LegislatorTerm.covering` adds the end check on top for real terms (see [[docs/explanation/legislator-term-current-and-covering.md|legislator-term-current-and-covering.md]]). `#running_on` (below) is the method that answers "in office on this day." `TermWindow` itself has no database — every caller supplies the candidate terms.

## Why running_term_start_year counts forward, never backward

`#running_term_start_year` finds the start year of the term running on a date, counted in steps of `years_long` from the year a person first took the seat.

Terms lie end to end with no gap, so counting forward from a real first year always lands on the current one — a senator seated in 2013 is now in the term that began `2013 + 6 + 6`, not still the 2013 one.

`years_long` is a caller argument, not read off the locale, because it belongs to the OFFICE (2 years for a rep, 6 for a senator, same locale).

The method never counts backward past `first_year`: a not-yet-seated person's answer stays in the future, so `#running_on` correctly reports that they are not serving.

## Why cycle_start_year walks from an anchor rather than sweeping candidates

`#cycle_start_year(sway_locale, date)` is the inverse of `#convening_date` — it reads a term year off a real event (a cast vote, for example) instead of a row's timestamps.

It walks from the locale's cycle anchor rather than sweeping a candidate list, so it cannot run off the end of a hard-coded range.

`#cycle_ends_on` answers the same boundary question as `#ends_on`, but for a cycle rather than a term that already knows its own end year.

## Why term_window_spec.rb tests against Struct stand-ins, not real LegislatorTerm records

`.covering` only ever asks a term for `term_start_year` and `sway_locale`, which is exactly what `LegislatorTerm.covering` hands it.

`.covering` only ever asks a term for `term_start_year` and `sway_locale`, which is exactly what `LegislatorTerm.covering` hands it — so `term_window_spec.rb` tests it against small `Struct`-based stand-ins (`TermWindowCandidate`) rather than real `LegislatorTerm` records. `Struct` is used rather than `OpenStruct`, which the Ruby 4.0 standard library no longer ships, matching what `github_pr_service_spec.rb` does.

`.running_on` also reads `term_end_year`, which the `.covering` stand-in does not carry — `.covering` never needed to know when a term finished. It reads `ended_on` too: the real day the term stopped, where a source published one or Sway observed it. `nil` means the locale's handover day decides. A `Struct` leaves any member the caller omits as `nil`, so the existing three-argument stand-ins (built for `.covering`) keep working unchanged and mean "no end date published" for the `.running_on` examples that reuse them.

## Why the spec refuses a locale with no declared rule instead of using another's

This used to answer, and the answer was Baltimore's: anything that was neither Congress nor a state fell through to the city charter (the same defect [[docs/explanation/term-rules-design.md|term-rules-design.md]] describes).

Registering a user creates a locale row for their city and their state (`Address#sway_locales`), so production already holds locales Sway has no calendar for. Refusing is the only honest answer for them.

## Why a term carrying its real end day matters

A term is stored as two YEARS, and every seat changes hands on one day, so a term that really ended in July is otherwise widened to the next January.

Eight people who left Congress during 2026 read as in office until 3 January 2027 because of it, and two seats showed two people at once. A real end date recorded on the term is what stops that.

## Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day

`app/frontend/sway_utils/termWindow.ts` is the one place that writes a term's window as words on the frontend.

Sway stores a term as two YEARS, which is the election cycle, not the person. Where it also holds the real day somebody arrived or left, that day is shown instead of the year at that end — so a member who served part of a cycle stops reading as having held all of it. Three pages built this string themselves before this existed.

`formatTermWindow` renders `"2025–2027"`, or `"Mar 4, 2025–2027"` for somebody who arrived mid-cycle, or `"2025–Jul 11, 2026"` for somebody who left early. It returns null when either end is unknown, which is what the pages already did with a legislator holding no terms — they draw nothing rather than half a window.
