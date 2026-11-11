---
mode: explanation
summary: "Explains the PARITY_COPY snapshot-testing pattern: user-facing strings live in a parityCopy.ts constant, and a matching Ruby constant in each page's request spec pins the exact values."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# The PARITY_COPY snapshot-testing pattern

Several Inertia pages moved their user-facing text out of components and
into `PARITY_COPY` constants in `parityCopy.ts`, so the page shows exactly
the same words it always did, character for character. A matching request
spec (for example `spec/requests/legislators_parity_copy_spec.rb`,
`bills_parity_copy_spec.rb`, `memberships_parity_copy_spec.rb`) checks
three things for its page:

1. That Inertia renders the expected component.
2. That the `PARITY_COPY` strings match their expected values, so nothing
   drifted.
3. That the page answers `200` for a signed-in user.

Each spec keeps its own `PARITY_COPY_VALUES_*` constant, copied by hand from
`parityCopy.ts`, so any difference between the TypeScript file and the
values here shows up as soon as one drifts from the other. Keeping the two
in sync is a manual step: nothing generates one from the other.

## Why parityCopy.test.ts checks the nested shape

Checks that `parityCopy.ts` keeps its wording grouped into nested objects, the
shape the web side reads.

These tests used to look up flat names such as `billsTitle`. A later reshuffle
grouped them, so the same string is now read as `bills.title`. The strings did
not change at all; only the path to reach them did.

## Why the values are copied by hand instead of read from the file

Reading `parityCopy.ts` directly from a request spec would mean running a
JS runtime, and running that file needs a DOM or it crashes — plain `as
const` strings and small lambdas are written out again in Ruby instead,
treated as the reference copy. The request-spec examples compare against
these copies, which is what makes any edit to `parityCopy.ts` that changes
a string fail this spec.

## Why `parityCopy.ts` stands alone

The file carries its own header: stands alone — no browser APIs, no React,
no MUI, no imports from `./index`. The web app (through the re-export in
`index.ts`) and the mobile app (through a direct relative import) both
load this exact file, so every piece of wording lives in one place and the
two apps cannot drift apart.

## Mobile's twin: `mobile/__tests__/parityCopy.spec.ts`

Guard rail for the shape of `parityCopy.ts`: the shared wording is grouped
into nested objects rather than one flat list of camelCase keys. These six
tests were written before that regrouping, so at first they all failed on
purpose. They started passing once `parityCopy.ts` was restructured, and
they now stop the flat keys from coming back. Do not mark any test here
with `skip` or `xtest` — a failure is the warning.
