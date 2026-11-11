---
lat:
  mode: explanation
---

# Baltimore one-person-per-legislator migration verification

`spec/production_readiness/production_baltimore_one_person_spec.rb` reads Baltimore's two-rows-per-person legislator data.

`spec/production_readiness/production_baltimore_one_person_spec.rb` reads Baltimore's two-rows-per-person legislator data, joined into one row, after the whole migration chain has run against a real production snapshot (see [[docs/explanation/production-snapshot-deploy-rehearsal-harness.md|Production snapshot: a deploy rehearsal harness]] for how the snapshot itself works).

After the join, each person has one row, and every vote either of their former rows cast is on it.

## Why the join is by person, not by name or by seat

"Keeps the people who left, with their own records" checks four legislators who are NOT joined into anyone else's row.

The four who left are the point of not joining by name or by seat: Nick Mosby was Council President for 2020-2024 and Zeke Cohen succeeded him, so a rule keyed on the office would have written one man's record as the other's.

## Why votes need their own coverage check

A person's votes were split across the two rows before the join.

`LegislatorTerm.covering` can only find a term on the row it is asked about, which is why a vote cast in 2021 could fall outside every term of the row that was in office at the time — if the join had not moved that vote onto the row whose term actually covers it.

The date a bill is placed by is the one `ScoreRecomputeService` anchors on — the house vote, or the senate vote, or failing both the day it was introduced — so "puts every vote inside a term that person really held" asks the same question the scoring does.

## Why the vote-coverage check is widened past Baltimore

"Leaves no vote in any locale for the earliest-term fallback to catch" is widened past Baltimore on purpose.

`LegislatorTerm.covering` answers a vote it cannot place with the person's EARLIEST term and a warning nothing reads — filing a bill under a term it predates, quietly. Whether that fallback is the right answer is still open, and this check says how much rests on it: across every recorded vote in every locale, nothing reaches it.
