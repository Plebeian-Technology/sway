---
lat:
  mode: explanation
---

# production_term_seats_spec.rb design

The original seeder stamped every term with the seat the member holds NOW, so anyone who changed seat kept their older terms filed under the new one.

Production rows can disagree with the seat the published history names, and a term's seat decides which district a vote counted under it belongs to. The data migration `20260807000001` repoints those rows. (See [[docs/explanation/seed-legislator-terms-add-correct-retire.md|"Why CORRECT never touches the seat"]] for why the ongoing seeder itself never does this — this migration is a one-time repoint of rows the seeder already got wrong before that rule existed.)

`spec/production_readiness/production_term_seats_spec.rb` pins the OUTCOME on the real snapshot, not the migration's own log lines: after the deploy chain replays, those rows carry the proven seat, NO stored Congress term disagrees with the committed roster's history, and the locale score rows under two of the terms keep their exact counts — a locale tally compares the whole jurisdiction's voters, which no seat change moves.

## The standing invariant

"leaves no stored Congress term disagreeing with the history's seat" is the standing invariant, checked on every snapshot generation: no stored Congress term may disagree with the seat the published history proves for it.

This catches the rows fixed by the migration, and any future drift — an upstream correction, or a seeder change that starts writing seats wrongly again.

## What spec/migrations/correct_wrong_seat_congress_terms_spec.rb pins

Unlike the production-snapshot spec above, this migration spec does not pin the names — that is the production-snapshot spec's job.

What it pins is the guards: only a term filed under the WRONG seat moves, and everything nearby stays put.

Its three distinctively-named helper methods (`run_seat_correction` and its neighbors) are named that way on purpose: Steep cannot see a method defined inside a `describe` block, so each one is declared in `sig-test`'s `Object` shim — and that shim holds ONE signature per method name for the whole suite. A plain `seat` or `person` here would take the name away from every other spec.
