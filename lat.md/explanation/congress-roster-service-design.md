---
lat:
  mode: explanation
---

# Why CongressRoster reads stretches of service, not terms

`CongressRoster` reads the committed `legislators.json` seed file to answer two questions about a bioguide id at a given year.

`CongressRoster` reads the committed `legislators.json` seed file to answer two questions about a bioguide id at a given year: which chamber they sat in (`#title_in`, "Sen." or "Rep."), and when their service in that stretch ended (`#service_ended_in`).

## Why it reads terms.item as stretches rather than trusting a stored term's own title

Each `terms.item` entry names the chamber a member sat in, the year they first took that seat, and — once they have left it — the year they stopped.

That is the only record Sway keeps of WHICH chamber somebody was in during a given year, because a stored `LegislatorTerm` row cannot answer that for itself: 691 of the 807 Congress terms in production carry no title at all, so nothing on the row says whether it should run two years or six. `CongressRoster` reads the seed file's own `terms.item` entries directly rather than relying on anything derived and stored on the term row.

## Why a departed member's entry still counts

Sitting members appear in the file, and so do the people Sway still shows in office whom congress.gov no longer lists — see [[docs/explanation/legislators-cache-departed-member-entries.md|the departed-member-entries doc]] for how those entries get folded back into the roster in the first place.

Both kinds carry usable `terms.item` history. A departed member's entry is marked `"currentMember": false` and carries the real terms the `unitedstates/congress-legislators` history proves, so the seeder can correct the term rows they were left with — see [[docs/explanation/congress-term-history-unbroken-service.md|the term-history doc]]. Anybody who has left AND was never folded back into the fetched roster this way is simply absent from the file entirely, and `CongressRoster` expects a caller to leave their rows alone rather than guess at a title for them.

## Why stretch_in falls back to the most recent stretch that had already begun

When no stretch covers the requested year exactly.

When no stretch covers the requested year exactly — a gap between two runs of service, or a year after the last recorded stretch closed — the most recent stretch whose start year is on or before the requested year is the best answer the roster file can give, rather than answering `nil`.
