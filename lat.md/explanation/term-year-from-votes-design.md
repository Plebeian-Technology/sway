---
lat:
  mode: explanation
---

# Why TermYearFromVotes is built the way it is

`TermYearFromVotes` works out which election cycle a legislator's own votes prove they served in.

A vote is a fact about holding the seat — a legislator can only cast one while they hold it — which makes it better evidence than any timestamp on the row, and it is evidence Sway already stores.

## Why this exists: the backfill's last_seeded_at bug

This class exists because the term backfill decided a legislator's cycle from `last_seeded_at`, the timestamp of when the seeder last wrote that row.

The seeder refreshes old rows too, so that timestamp creeps forward to the present, and every row landed in the CURRENT cycle — including people who had already left office in 2024. This is a distinct bug from the `LegislatorTerm.current`/`.covering` fix documented in [[docs/explanation/legislator-term-current-and-covering.md|the legislator-term-current-and-covering doc]]; both surfaced together, but they fix different code.

`#call` returns `nil` rather than guessing whenever the votes don't settle the question on their own — no votes at all, or votes spread across more than one cycle. A term Sway cannot prove from the votes is left exactly as it is, because Sway never invents domain data.

## Why more than one cycle among the votes means nil, not a guess

`#cycle_years` collects the DISTINCT election cycles a legislator's votes fall in.

More than one means they served across a handover, which a single term year cannot describe on its own — the caller is told nothing rather than told something wrong.

## Why voted_while_this_row_existed? exists

Not every vote hanging off a `Legislator` row was actually cast by the person that row currently stands for.

The term backfill merged duplicate identities and moved the losing rows' votes onto the surviving one, so a row can carry votes cast BEFORE that row existed. Three sitting members of Congress were found in exactly that state: their rows were created in July 2026, yet they carried votes from the cycle that ended in January 2025.

A row cannot have served a term that was already over before the row was created. When the evidence looks like it did, the votes came from somewhere else (an earlier, now-merged identity) and are no evidence about THIS row at all — `#call` returns `nil` rather than reporting a cycle the row never actually lived through.

## Why sway_locale re-declares a non-nil return instead of reusing call's guard

Every private method below runs only after `#call` has already returned early when `legislator.sway_locale` is nil.

`#sway_locale` re-reads and memoizes `legislator.sway_locale` with its own non-nil return, because Steep does not carry a `return nil if ...` guard in one method across to narrow a value read again in a different method — declaring the non-nil return here is what lets the type checker treat every caller below as safe.

## What spec/data/correct_term_years_from_votes_spec.rb's fixtures rebuild

The spec rebuilds the shape production was actually in and checks the migration puts it right.

Production had three generations of Baltimore rows for the same 16 people, and every one of the 48 terms said 2024-2028 — including four members who left office in 2024. The cause was the term backfill reading `last_seeded_at`, which the seeder pushes forward on old rows too.

`departed_member_with` builds one legislator carrying the defect: a term stamped with the CURRENT cycle, a `last_seeded_at` that explains why, and votes that prove otherwise. Its default `created_on` is set to `2024-05-06`, as production's 2020-generation rows were: inside the cycle they served, which is what makes their votes their own.

The "leaves a row alone when its votes predate the row itself" example is the production case this guard was written for. The backfill moved the losing rows' votes onto the surviving row, so three sitting members of Congress have rows created in July 2026 carrying votes from the cycle that ended in January 2025. Following those votes would have moved two of them onto a finished term and dropped them off the site.
