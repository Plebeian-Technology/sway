---
mode: reference
summary: Contract for useDistrictStats — the embedded-vs-fetched data path and the field shapes it matches to Rails' bill-score tally.
status: agent-extracted
related: []
---

# useDistrictStats hook

`useDistrictStats` (`mobile/src/hooks/useDistrictStats.ts`) reports how a
bill's own district voted.

It picks the value out of data already available, and only fetches when it
has to:

- If the `/bills/:id` response passed in as `fromBill` already carries
  `district_stats` — the preferred route, since one request serves both the
  website and this app — the hook simply reads it and asks for nothing.
- If it does not, the hook requests `GET /bills/:id/district_stats` on its
  own. Rails does not serve that route yet. The day it does, this hook
  starts using it with no further change.

The fields match how Rails already tallies a bill score: `for_count`,
`against_count`, `abstain_count`, `total`. `majority` is worked out from
those counts and handed over as a plain label, so no screen has to redo the
comparison.
