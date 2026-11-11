---
mode: explanation
summary: "Why currentAddressWithout rebuilds a visit's address from the screen's own query string, names its owned params explicitly, and is a helper rather than a router interceptor."
status: agent-extracted
related: [docs/explanation/pipeline-controls-empty-stage-selection-wire-format.md, docs/reference/pipeline-controls-state-url-contract.md]
---
<!-- vale Vale.Spelling = NO -->

# currentAddressWithout: owned params, not a global interceptor

`currentAddressWithout` (`app/frontend/sway_utils/currentAddressWithout.ts`)
builds the address a router visit should use, starting from the address
already on screen rather than from a bare path.

## Why a visit must not start from `window.location.pathname`

Inertia lays a visit's `data` OVER the query string of the href it is
given — `mergeDataIntoQueryString` does `url.search = stringify({
...parse(url.search), ...data })` (`@inertiajs/core` 3.6.1). A bare
pathname carries no query, so there is nothing to lay the data over, and
every parameter the visit did not name is dropped. On the Bill Creator's
pipeline tab that is `?run_id=` — the pin the summary tab's failure alert
links to, and the only thing telling `LegislationPipelineRunSourcing` which
run to surface — and `?sway_locale_id=`. `replace: true` does not save it:
that chooses `history.replaceState` over `pushState` and says nothing about
the query string.

## Why the call site still names its own parameters

Because the merge keeps a parameter the data leaves out, a value the
operator has just cleared would otherwise survive from the old address —
deselecting back to every stage leaves `selected_stages` out of the data,
and the old list would stand. So `owned` names the parameters this visit
decides for itself, and they come off the address before the merge.
Absence and deliberate removal look identical to a merge, and only the
caller knows which it meant.

## Why this was historically a helper rather than an unguarded router interceptor

Historically, `currentAddressWithout` was introduced as a plain helper each call site
invoked rather than an unguarded `router.on("before")` interceptor, because an
interceptor lacking an explicit clearance protocol could not distinguish an omitted
parameter from one removed on purpose. An unguarded interceptor would have undone
deliberate removals across the app: `RunSelector` dropping `run_id` for "Latest run (auto)",
`useLocale` dropping `page`, and the `resetParams` lists `useUrlSort` and
`useDebouncedUrlSearch` exist to honour.

Under the canonical navigation carry architecture documented in
`lat.md/explanation/query-parameter-navigation-carry.md`, this limitation is resolved
by the universal empty-value clearance protocol (`?param=`). With an explicit clearance
signal, centralized interception safely distinguishes deliberate removal from omission
and carries query parameters without resurrecting cleared values.

## Two spellings, one call

Each name is removed in two spellings. Inertia serializes an array
parameter through `qs` in "brackets" format, so `selected_stages` sits in
the address as `selected_stages[]`, and a caller should not have to know
that.

## The pathname carries the bill

The pathname is passed through untouched, which is what carries the bill:
the Bill Creator puts the bill id and the tab in the PATH, deliberately and
with a note saying so (`BillCreatorShell`'s `onBillChange`). See
[why an empty stage selection has to be spelled out on the wire](pipeline-controls-empty-stage-selection-wire-format.md)
and [pipeline controls state: URL prop and param contract](../reference/pipeline-controls-state-url-contract.md)
for the rest of the query-param contract this helper participates in.
