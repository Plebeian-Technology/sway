---
lat:
  mode: explanation
---

# Why TermRules and TermRulesRegistry are built this way

Why SwayLocale::TermRules and TermRulesRegistry declare each locale's term calendar in code with citations, and the Baltimore/Congress-specific history behind individual declarations.

## The problem TermRules replaced

Sway used to work out term-calendar behavior by asking a locale which KIND it was — is this Congress, is this a state — and everything that was neither fell through to Baltimore's city charter.

A locale added later would then take office on the Thursday after the first Monday in December, on a four-year cycle counted from 2024, with nothing saying so. Every answer about which term a vote belongs to, and about who holds office today, rests on these dates.

The rules split into two kinds:

- **The calendar** (`convening`, `cycle_anchor_year`, `cycle_years`) says
  when a term runs. It is law. `TermWindow` reads it for every date
  question in the app.
- **What the roster source can prove** is not law — it is a limit of
  whoever publishes the jurisdiction's roster. It decides what Sway is
  allowed to conclude from that file. See
  [[docs/explanation/retire-departed-members-safety-design.md|retire-departed-members-safety-design.md]]
  for `roster_lists_only_current_members` and `publishes_term_history`,
  which is why the departed-member fix works for Congress and
  not (without a further fix) for Maryland.

`TermRules::Undeclared` is raised loudly on purpose: a wrong convening date produces confident wrong answers rather than an error, so refusing is safer than guessing.

## Why cycle_anchor_year/cycle_years are what they are

`cycle_anchor_year` is a year in which a cycle really began; `cycle_years` is how many years one runs.

`TermWindow` walks from a date back to the cycle that contained it using this pair. `cycle_years` is the locale's DEFAULT only — an office can run longer than the locale's default cycle (a U.S. senator serves six years where the House's cycle is two), so the caller passes the real length in rather than reading it from here.

## Why publishes_exact_term_dates exists with no reader yet

`publishes_exact_term_dates` is true when a source gives the exact DAY a term ended, not just the year.

Sway stores a term as two years today, so nothing reads this attribute yet — it records which locales could support a real end date, ahead of the work to use one.

## Why the declarations live in code, with citations

`TermRulesRegistry::DECLARATIONS` lives in code rather than in the database or in `locales.json`, for one reason: these are law, and the citation that proves each one belongs beside it.

Nobody tunes them from an admin screen, and a wrong value here is not visible in any screen either — it just makes every vote-to-term answer wrong for that locale. Adding a locale means adding an entry here; until then, that locale raises `TermRules::Undeclared` the first time anything asks it a date question, rather than silently borrowing Baltimore's charter the way the previous arrangement did.

All three citations were read against the primary sources: the Constitution via law.cornell.edu, the Maryland Manual and Const. Art. III via msa.maryland.gov, and the charter text via codes.baltimorecity.gov.

`CONGRESS_LOCALE_NAME` is named because `CongressTermHistory` reads Congress's handover day straight off the declaration, without a database row to ask.

## Why Baltimore uses one convening rule for all 16 legislators

Baltimore City Charter Art.

III § 2(a)(2) sets a council member's term to commence "the Thursday next after the first Monday in December succeeding their election." The Mayor's term commences the TUESDAY after the first Monday instead (Art. IV § 1) — a different day. Baltimore's declaration uses the council's rule for all 16 Baltimore legislators anyway: 15 of the 16 are council seats, and Baltimore publishes no per-member roll-calls, so the two-day difference cannot change which term a cast vote lands in.

## The two convening-rule wordings

Two wordings cover every locale Sway holds today: a law either names a calendar day outright, or points at a weekday.

### FixedDayConvening

A term begins on the same calendar day every cycle, because the law names that day outright — no weekday arithmetic is involved.

Congress is the only locale of this shape today: the 20th Amendment fixes 3 January, whatever weekday that falls on.

### NthWeekdayConvening

A term begins on a weekday the law picks out rather than on a fixed date — "the second Wednesday of January", or "the Thursday next after the first Monday in December". The day therefore moves from cycle to cycle.

`weekday` and `ordinal` find the day the law counts from. `offset_days` moves on from there when the law names a different day of the same week: Baltimore counts to the first Monday and then starts three days later, on the Thursday. `weekday` follows `Date#cwday` — Monday is 1, Sunday is 7.

## Congress's declaration

U.S. Const.

Amend. XX §1: "the terms of Senators and Representatives \[end] at noon on the 3d day of January ... and the terms of their successors shall then begin" — a named day, not a weekday rule, which is why Congress declares `FixedDayConvening`.

The cycle length declared here is the House's two years. A senator serves six, which the caller passes in — see "Why cycle_anchor_year/cycle_years are what they are" above.

## Why Baltimore's roster_lists_only_current_members went from false to true

The Open Baltimore portal republishes one tidy record per SEAT and names whoever holds it, so the file is the sitting council and nobody else — but this value said `false` until the identity model changed.

The reason given at the time was that the roster is keyed by seat, so a successor's record overwrote the previous occupant's row and nobody ever fell out of the file. That was a statement about Sway's identity model, not about the source itself. Now that a person is identified by the seat AND the name published under it (see [[docs/explanation/legislator-identity-value-design.md|legislator-identity-value-design.md]]), the previous occupant does fall out of the roster when they leave — which is what makes their departure observable, and is why the value could become `true`.
