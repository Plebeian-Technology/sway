---
mode: explanation
summary: "Why every legislator preparer's term-year methods must return a non-nil Integer, and why authoritative_term? exists to keep a synthesized fallback year from being reported as a proven term."
status: agent-extracted
related: [docs/explanation/seed-legislator-terms-add-correct-retire.md]
---

# Why preparer term-year methods can never return nil

`SeedPreparers::Legislators::Base#term_start_year` and `#term_end_year` are a
hard contract: every subclass must return a non-nil Integer for every input,
including source blobs that omit all term fields. The database forbids NULL
in `legislator_terms.term_start_year` and `term_end_year`, and these values
feed that INSERT directly; a nil here aborts the insert when seeding a new
member.

Every preparer also exposes `authoritative_term?`, which is true ONLY when
the source blob carried a real term year. `SeedLegislatorTerms` reads this
flag so a synthesized fallback year is never reported as a proven prior term
via `#proven_terms` — Sway never fabricates domain data.
