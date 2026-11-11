---
mode: explanation
summary: "Explains why FetchBillsService filters malformed Legistar response rows, and why that filtering happens after the empty check but before reading the pagination cursor."
status: agent-extracted
related: []
---

# Filtering malformed API response rows

<!-- vale Vale.Spelling = NO -->

Why `FetchBillsService#fetch_all_matters` filters out malformed rows from a
Legistar page, and why that filtering happens in a specific order relative
to the pagination cursor.

## Filter the rows, not just the page

`FetchBillsService#fetch_all_matters` pages through Legistar's `Matters`
endpoint. Each page is a JSON array, but nothing guarantees every element of
that array is a well-formed row (a `Hash`).

Two things downstream reach into a raw row without checking its type first:
the pagination cursor read (finding the last `MatterId` on the page), and
`FetchBillsService#build_metadata`'s read of `matter["MatterTypeName"]`.
`FetchBillsService#call_discover` only rescues `Faraday::Error` and
`Legistar::Client::Error` around this stage, so a single `nil` (or otherwise
non-`Hash`) row in a page would raise `NoMethodError` and kill the entire
run at its very first stage — before even one bill had been saved.

`#fetch_all_matters` filters each page down to `Hash` rows before doing
anything else with it. `FetchBillsService#fetch_attachments` and
`FetchHearingsService#fetch_matter_attachments` filter their own Legistar
responses the same way, for the same reason: `#select_primary_attachment`
starts by reading `a["MatterAttachmentFileName"]` on every element, so a
null row there would raise `NoMethodError` straight through
`#fetch_attachments_safely` (which rescues network errors only) and out of
`#call_discover` (Faraday and Legistar errors only) — a `StageError` that
would fail the entire run at its first stage.

## Filtering happens after the empty check, before the cursor read

The filter step sits in a specific place in the loop: AFTER the page's
empty check, but BEFORE the pagination cursor (`last_id`) is read from the
page.

That ordering matters because the loop's own stopping condition
(`page.size < PAGE_SIZE`) reads the RAW page size — the count of everything
Legistar actually sent, before filtering. Filtering before that check would
make a page of pure garbage rows look like the end of the list, when it is
really just a page Legistar happened to fill with bad data. Filtering after
the check keeps the loop's stopping logic accurate, while still protecting
the cursor read and `#build_metadata` from a row that is not a `Hash`.

## Related

See also
[Bill external ID validation](bill-external-id-validation.md) for the
companion defense against untrusted *values* inside an otherwise
well-formed row (as opposed to a row that is not a `Hash` at all).

## Why the fetched year window is computed, not a fixed list

`FetchBillsService#default_years` returns the last two calendar years — last
year and this one — read from the clock. Writing the years down as a fixed
list such as `[2025, 2026]` would have quietly stopped finding new bills
from Jan 1, 2027 onward.

## Why a bad page ends the loop instead of raising

Inside `#fetch_all_matters`'s paging loop, a page request that raises
`Legistar::Client::HttpError` or `Legistar::Client::ParseError` (an error
status, or a body that is not JSON) is treated as the end of the list: the
loop breaks and keeps whatever matters it already gathered. Real network
failures are different — they stay a bare `Legistar::Client::Error` and
still travel up to `#call_discover`'s "fetch_bills network error" wrapper.

## Why pagination stops when the cursor stops advancing

`#fetch_all_matters` stops paging when the tail `MatterId` on a page is
missing or is not an `Integer`, rather than keeping the previous cursor and
asking again. Reusing the old cursor would send the identical `MatterId gt`
query forever, until the job hit Solid Queue's 4-hour limit. The loop logs
a warning and stops instead, so the operator notices.
