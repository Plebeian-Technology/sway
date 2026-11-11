---
mode: explanation
summary: "Why the CongressDotGov seed preparer's #party test proves the memoized value is not recomputed on a second call, closing the gap left by a dead @_party guard."
status: agent-extracted
related: []
---

# Proving `CongressDotGov#party` actually memoizes

`spec/db/seeds/seed_preparers/legislators/congress_dot_gov_spec.rb`'s
"does NOT recompute on the second call (WR-04: `@_party` guard was dead)"
example wrecks the source data (`json`) after the first call to `#party`,
to prove the second call reads the cached value instead of working it out
again. If the memoization guard were still broken — reading `@_party`
while writing `@party` — the second call would start over, and `json` is
now empty, so it would come back with a different, wrong answer instead of
the first call's cached result.
