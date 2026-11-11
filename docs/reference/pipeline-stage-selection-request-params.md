---
mode: reference
summary: "Documents the accepted request-parameter formats for pipeline stage selection, and the meaning of nil versus an empty selection."
status: agent-extracted
related: []
---

# Pipeline stage selection request parameters

`requested_stage_names` reads the stage names an address asks for, before
any allow-listing is applied.

## Accepted formats

- `?selected_stages=` is the current parameter name; `?stages=` is accepted
  as its older spelling.
- The value arrives as an Array when the browser sends a repeated
  parameter (`selected_stages[]=a&selected_stages[]=b`).
- The value arrives as a String when an older bookmarked address sends one
  comma-separated value (`selected_stages=a,b`). The string is split on
  commas, and each piece is stripped and empty entries are dropped.

## nil versus an empty selection

- `nil` means the address named no stages at all.
- An empty array means the address named stages, but none of them matched a
  recognized stage key.

Callers must treat these two cases differently: no selection yet defaults to
every stage; an explicit selection of nothing recognized defaults to no
stages.
