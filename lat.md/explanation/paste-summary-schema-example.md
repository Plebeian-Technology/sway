---
lat:
  mode: explanation
---

# Why PASTE_SUMMARY_SCHEMA_EXAMPLE is written by hand

An example of what an operator should paste, matching the shape defined in `config/schemas/bill_summary.json`.

It is written out by hand here rather than sent down from the server, which keeps the coupling low: the parent component holds the source of truth, and later this could be handed in as a prop read from that schema file without changing anything about the dialog's interface.

## Test notes

`PASTE_SUMMARY_SCHEMA_EXAMPLE` is the only place operators see a valid paste payload. It must not show `draft_org_positions` — positions must come only from testimony, not a pasted summary.

`config/schemas/bill_summary.json` requires `summary_markdown` and forbids extra keys, so every key here must be schema-accepted or a copied example gets rejected.
