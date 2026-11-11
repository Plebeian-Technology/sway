---
lat:
  mode: explanation
---

# Why LegislatorsCache::DepartedMemberEntries is built the way it is

`DepartedMemberEntries` builds roster entries for the people Sway still shows in office whom congress.gov no longer lists.

## Why this exists

The Congress roster is rebuilt every week from whoever congress.gov calls a current member.

Somebody who leaves simply falls out of it, so the seeder never looks at their row again, and the term row they were left with runs on for years. Sway works out who is in office by reading the year a term ends, so they keep showing as sitting.

`RetireDepartedMembersService` (see [[docs/explanation/retire-departed-members-safety-design.md|its own doc]]) solves the same class of problem for locales whose roster source lists ONLY people currently in office, by observing an end date and marking it as such. Congress's roster source does NOT work that way — congress.gov simply omits departed members rather than flagging them — so that service does not apply here. `DepartedMemberEntries` is the Congress-specific answer: put the departed person BACK into the fetched list so `CongressTermHistory` (a source that DOES publish whole past terms with real end dates) can supply the real end date, rather than observing one.

## What is and is not invented here

Every value in the entry this class builds is copied off the person's own existing row.

No term is written here. The caller (`BaseRefresh#departed_members`) hands these entries to `CongressTermHistory` like any other roster entry, and that source answers with the real terms — including the year the person actually left, which is the fact the roster could not carry on its own.

## Why only people still reading as in office are covered

`#still_in_office` only returns Legislators whose stored term is still running today.

Those are exactly the rows that are wrong. Once a person's terms are corrected by the `CongressTermHistory` merge, they stop reading as in office, so the next weekly refresh drops them from this list again — the roster does not grow without end. Anybody who leaves later is still in office at the moment they leave, so they get picked up in their own turn, the same way.

`#still_in_office` is asked through `TermWindow`, the same choke point `Legislator#serving?` goes through, so this list can never drift from what a reader sees on the legislators page.

## Why entry_for returns nil for a row with no seat to name

No row this codebase writes should be able to reach that branch: a term cannot exist without a district, a district name is always a state code followed by a number, and `#still_in_office` only yields people who hold a term.

The guard exists for a row that arrived some other way — a hand edit, an old migration — because the alternative is an entry with no state, which makes the seed preparer raise and takes the whole seed down with it.

## Why the entry carries "currentMember" => false

That mark is what stops the seeder inventing a fresh current term for somebody who is not actually serving — see `SeedLegislatorTerms`.

Without it, folding a departed member back into the fetched list would make them look freshly re-elected.

## Why entries come back sorted by bioguide id

Newest-seat-first is not meaningful for this list. Entries are sorted by id purely so the written file is stable between runs — otherwise `#changed?` would report a difference that is only a reordering, every single week.
