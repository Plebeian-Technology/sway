---
mode: explanation
summary: "Why LegislatorsCache::CongressRefresh takes two independently-injectable sources, drops each member's updateDate before diffing, hand-carries the President entry, and folds in departed members before asking for term history."
status: agent-extracted
related: [docs/explanation/seed-legislator-terms-add-correct-retire.md, docs/explanation/retire-departed-members-safety-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `LegislatorsCache::CongressRefresh` is built the way it is

`CongressRefresh` fetches the current list of members of Congress from the
congress.gov v3 API, keeps the hand-written President entry first in the
list, and returns a `Result` whose `changed_files` is filled in only when
the freshly built JSON differs from the seed file already on disk.

## Why it takes two independently-injectable sources

This class reads TWO sources on two different hosts — congress.gov itself,
and `CongressTermHistory`'s own connection to the
`unitedstates/congress-legislators` project — so a spec that wants to stay
offline has to close both doors. `connection:` takes the place of the
congress.gov call, the same way `Legistar::Client` works elsewhere.
`term_history:` takes the place of the term-date source separately,
because `CongressTermHistory` builds its own connection to a different
host and cannot share the first one. Passing only `connection:` still
reaches the network through the term-history source.

## Why `updateDate` is dropped from the output, and stripped again before diffing

congress.gov moves the `updateDate` timestamp on its own schedule, whether
or not anyone joined or left Congress. `#fetch_all_members` drops it from
every member entry before writing the output JSON — keeping it would make
`#changed?` report a difference on almost every run, opening a pull request full of
noise and re-stamping `legislators_cache_fetched_at` every week even when
the roster is identical. No seed preparer reads that field.

`#normalize_for_diff` strips it again, this time from BOTH sides of the
comparison, before `#changed?` runs. The committed seed file still carries
`updateDate` from back when it was generated, while freshly fetched data
no longer does (the output-side strip above already removed it) — without
this second strip, the very first run after this change shipped would
always look changed purely because of the field's asymmetric presence.

## Why the President entry is hand-carried, never fetched

`POTUS_BIOGUIDE_ID` and `#potus_entry` exist because congress.gov does not
list the President, and neither does the term-history source. Sway writes
this entry by hand into the seed file, and `#fetch_all_members` puts it
first in the list whenever one is present, reading it back out of the
existing seed file rather than the API on every run. `#potus_entry`
returns `nil` (never an empty hash) when the seed file is missing or holds
no President entry, so the caller can skip it cleanly — a blank entry in
the output would trip up code further down the line that expects every
entry to have a `bioguideId`.

## Why departed members are folded in before asking for term history

`#departed_members` adds entries for the people Sway still shows in office
whom the fetch did not name — see
[the RetireDepartedMembersService doc](retire-departed-members-safety-design.md)
for the twin mechanism that handles the same class of problem for locales
whose roster source does NOT keep departed members. Without these
entries, the roster would silently lose somebody the week they leave
Congress, and the stale term row they were left with could never be
corrected. They're added to the list before `#with_term_history` runs, so
their real terms — and the year they actually left — come from the same
term-history merge every other member goes through.

## Why `#with_term_history` replaces congress.gov's own term data

congress.gov reports one entry per Congress, so a six-year senate term
arrives as three two-year pieces, and every historical entry is silent
about which seat was held. Sway reads the end year to decide who is in
office and reads the seat to decide which votes belong to a term, so both
gaps matter — see `LegislatorsCache::CongressTermHistory` for how the real
history is built. A member the history source does not know about keeps
whatever congress.gov said, so somebody sworn in this week is never left
with no terms at all; how many members that was is logged, because a
source that has fallen behind must show up as a number rather than as
silence.

The `termsSource` mark written onto each merged member, and why an entry
carrying it must never be read as anything less than the complete term
history, is covered in
[the SeedLegislatorTerms doc](seed-legislator-terms-add-correct-retire.md#the-termssource-mark-and-its-shape-check-congressgov).
