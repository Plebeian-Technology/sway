---
mode: explanation
summary: "Why an empty pipeline-stage selection has to travel as a literal ?selected_stages= query string instead of an empty array."
status: agent-extracted
related: [pipeline-controls-state-url-contract.md]
---
<!-- vale Vale.Spelling = NO -->

# Why an empty stage selection has to be spelled out on the wire

`BillsController`'s pipeline-controls action reads `params[:selected_stages]`
to know which pipeline stages are selected. An empty selection cannot travel
as an empty array on either side of the request:

- `Rack::Utils.build_nested_query` turns `selected_stages: []` into an empty
  string when building a query, so a request built from that literal array
  sends no `selected_stages` parameter at all.
- Inertia's client pushes one query pair per array item, so a cleared stage
  list has no items to push either. It arrives instead as
  `?selected_stages=`, written into the address by
  `app/frontend/sway_utils/addressWithEmptyList.ts`.

Sending the literal query string `?selected_stages=` by hand is the only way
to express "nothing selected." Before this fix, unchecking the
last stage box sent no parameter at all, the controller read that absent
parameter as "every stage," and every checkbox ticked itself back on.

See [Pipeline controls state: URL prop and param contract](pipeline-controls-state-url-contract.md)
for the rest of the query-param contract, including the related legacy
`?stages=` fallback.
