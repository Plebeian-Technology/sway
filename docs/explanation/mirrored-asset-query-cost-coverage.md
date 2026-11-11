---
mode: explanation
summary: "Why spec/requests/mirrored_asset_query_cost_spec.rb exists, which surfaces it covers and doesn't, and why it measures at two list sizes rather than a fixed query ceiling."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why mirrored_asset_query_cost_spec.rb exists

A picture Sway holds a copy of is resolved through `MirroredAssetUrl`,
which reads an attachment row and then a blob row. Any surface that
serializes a **list** of such records pays that cost twice per row unless
it says so up front (preloads the attachment and blob).

## History

An earlier fix repaired the public organizations list, but nobody looked for the
same shape elsewhere. Four more surfaces had it, across two serializers,
and the largest was the bill page — the most visited screen in the app.

## Scope

- The public organizations list itself is pinned next to its own page, in
  `spec/requests/public/organizations_spec.rb`, not in this file.
- Current mirror declarations and their readers are defined in the
  [storage policy](../../lat.md/explanation/sway-google-cloud-storage.md#only-consumers-of-mirrored-assets-declare-the-callback).

## Why two sizes rather than a fixed ceiling

What matters is whether the query cost grows with the list length, not
what the absolute count is — a fixed ceiling has to be re-guessed every
time an unrelated query is added elsewhere on the page. The spec measures
a short list and then a longer one (adding records in between rather than
rebuilding fixtures) and asserts the read count holds steady between the
two sizes. Records are added, not rebuilt, because two bills in one locale
cannot share a release date, so the fixtures have to survive both rounds
of measurement.

The two-sizes check also refuses a round that read nothing: two zeroes are
equal and would read exactly like a page holding its cost steady, but a
page that stopped drawing pictures altogether looks the same from here as
one that never had a cost to measure.

## Why Bill#render sends flat organization rows, not whole records

`Bill#render`'s `organizations` prop maps
`active_organization_bill_positions` (preloaded with
`organization: {icon_attachment: :blob}`, the fix this file covers) to flat
rows — `{id, bill_id, organization, support, summary}` — rather than
sending whole `Organization` records, each carrying every position that
organization holds across every bill. The mobile app's stance filter reads
a top-level `support` field and could not parse the nested shape; the flat
row is also the smaller payload of the two, on the most visited page in the
app.
