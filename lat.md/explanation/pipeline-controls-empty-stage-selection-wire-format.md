---
lat:
  mode: explanation
---

# Why an empty stage selection has to be spelled out on the wire

`BillsController`'s pipeline-controls action reads `params[:selected_stages]` to know which pipeline stages are selected. An empty selection cannot travel as an empty array on either side of the request:

- `Rack::Utils.build_nested_query` turns `selected_stages: []` into an empty
  string when building a query, so a request built from that literal array
  sends no `selected_stages` parameter at all.
- Inertia's client pushes one query pair per array item, so a cleared stage
  list has no items to push either. It arrives instead as
  `?selected_stages=`, written into the address by
  `app/frontend/sway_utils/addressWithEmptyList.ts`.

Sending the literal query string `?selected_stages=` by hand is the only way to express "nothing selected." Before this fix, unchecking the last stage box sent no parameter at all, the controller read that absent parameter as "the default stage set," and those checkboxes ticked themselves back on.

See Pipeline controls state: URL prop and param contract for the rest of the query-param contract, including the related legacy `?stages=` fallback.
