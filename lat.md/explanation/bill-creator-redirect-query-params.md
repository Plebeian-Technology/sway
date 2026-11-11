---
lat:
  mode: explanation
---

# Bill Creator redirects: saved/event_key as path-helper query params

Several Bill Creator controllers (`LegislatorVotesController#create`.

Several Bill Creator controllers (`LegislatorVotesController#create`, `BillsController#create`, and others) redirect back into `creator_bill_creator_path` / `new_bill_creator_path` carrying `saved` and/or `event_key` in the query string, rather than passing them as `redirect_to` options.

## Why they go through the path helper

`saved` and `event_key` must go through the path helper so they land in the query string.

The success toast reads `saved` from the URL, and the accordion picks which panel to open from `event_key` in the URL when it mounts. Handing them to `redirect_to` as options instead drops them without a word — Rails only understands `:status` and the flash keys there.

## notice: rides the flash instead

Where a controller uses `redirect_to ..., notice.

Where a controller uses `redirect_to ..., notice: "..."` instead of a `?saved=` query param, that rides the Rails flash (shared via `inertia_share`) so `registerFlashToasts` shows it exactly once, rather than a `?saved=` param re-toasting every mounted section that reads it. `event_key` still travels as a query param in the same redirect — `BillCreatorAccordions` reads it to focus the relevant tab.
