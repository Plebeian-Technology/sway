---
mode: explanation
summary: "Why LegislatorsCache::CongressTermHistory exists as a second source, fetches its two files in size order, answers for nobody whose record could not be read whole, collapses covered terms, and reads the handover date from the locale's own declaration."
status: agent-extracted
related: [docs/explanation/retire-departed-members-safety-design.md, docs/explanation/legislators-cache-congress-roster-build.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `LegislatorsCache::CongressTermHistory` is built the way it is

`LegislatorsCache::CongressTermHistory` reads the real term-by-term
history of members of Congress from the `unitedstates/congress-legislators`
project. congress.gov names everybody currently in Congress and keeps
their photo, party, and contact details current, but it gives one entry
PER CONGRESS rather than one entry per term — a senator's six-year term
arrives as three two-year pieces. Sway decides who is in office by reading
the year a term ends, so recording a senate term as two years long would
put sitting senators out of office. This project publishes the real
terms, with real dates and the seat each one was served in.

It is safe that this source publishes slowly: a term that has already
ended never changes again, so news arriving a few weeks late cannot make
an old term wrong. A brand new member's own term still comes from the
congress.gov roster, which `CongressRefresh` fetches fresh every week.

For why each real term is widened to Sway's January-to-January years
rather than narrowed to its real dates, see
[the RetireDepartedMembersService doc's widening section](retire-departed-members-safety-design.md#why-a-stored-term-widens-to-hold-a-real-end-date-instead-of-narrowing)
— `#window` implements the same rule this class states: a senator
appointed until a special election in November must not read as out of
office the following January.

## Why the historical file is only fetched when the current file falls short

`.fetch` reads `legislators-current.json` first and only falls back to
`legislators-historical.json` for whoever it didn't answer for. That
happens when somebody has left Congress and this source has recorded it
before congress.gov has. The historical file is fetched lazily, on
condition, because it is 13 MB and Sway runs on one small machine — see
also [the FaradayStack doc](faraday-stack-retry-and-connection-design.md)
for why `.congress_legislators` gets a longer timeout than every other
connection profile. Everything either file says about anyone not asked
about is dropped as it is read.

## Why `#terms_of` answers for nobody whose record could not be read whole

`#terms_of` returns `[]` — not the terms that happened to parse — for a
person if even ONE of their published terms has a date `#window` cannot
read. A caller is entitled to treat what comes back from `#terms_for` as
the person's COMPLETE history: `SeedLegislatorTerms` deletes any stored
term this list does not name. Handing back only the terms that happened
to parse would turn one bad upstream date into a deleted term row, and for
a sitting member that means dropping out of office. Returning nothing
instead leaves them counted as unanswered (already logged via `#missing`)
and leaves every row they hold alone.

## Why `#keep_distinct` drops a term fully covered by another

A year-by-year record splits a mid-year move into two entries covering the
same cycle. Adam Schiff was a representative from 2023 until December
2024, then a senator for the three weeks left in that Congress. Both widen
to windows ending in January 2025, and the three-week Senate window sits
entirely inside the two-year House one. Keeping both would give him two
rows starting in the same cycle, and a vote he cast in May 2024 as a
representative would be filed under the Senate. Keeping only the longer
one puts every 2024 vote where it belongs. Terms that merely OVERLAP,
rather than one fully containing the other, are both kept — neither tells
the whole story on its own.

## Why the handover date comes from the locale's declaration, not a database row

`#january_of` reads the day Congress hands a seat over from
`SwayLocale::TermRulesRegistry`, the same declaration the rest of the app
uses, rather than a database row — this parser runs over static roster
files and has no `SwayLocale` record to hand. Reading the declaration
directly is what stops the widening math here from drifting away from the
date every other Congress-term calculation in the app uses.

## Why the real end day rides along beside the widened years

The widening above is what makes a term usable at all — Sway hands every
seat over on one January day — but it is also what leaves somebody who
left in July reading as in office until the next January. The real day
used to be read from the roster and then thrown away; now it comes
through, and the seeder writes it onto the term for a locale that declares
its source can give one.

For a member who left near the January boundary — Senator Rubio, who left
on 2025-01-20 — the widened year and the real day agree about the outcome:
a term past the 3rd is recorded as running to the NEXT January (2026,
already past), so he reads as out of office either way. For members who
left mid-2026, the widened year and the real day disagree, and the real
day is the only one of the pair that is right.
