---
mode: explanation
summary: "How spec/scraper/scraper/maryland/legislator_votes_spec.rb fakes PDF parsing, the mutation regression it pins, and why its 404-retry fake wraps a StringIO in OpenURI::Meta."
status: agent-extracted
related: []
---

# `Scraper::Maryland::LegislatorVotes` spec design notes

## How the Maryland scraper's PDF read is faked

The Maryland scraper gets its data in three steps: `result` is the raw
stream OpenURI downloaded, `PDF::Reader.new(result)` is the parsed PDF, and
`reader.pages.first.text` is the text votes are read out of. The spec fakes
things at the `PDF::Reader` level, so no real PDF and no network call are
needed.

## The mutation regression

When a URL comes back 404, `#do_request` retries against an earlier year.
It used to do that by changing `@bill.introduced_date_time_utc`, so if
anything later called `@bill.save`, the wound-back year got written to the
database. The retry now passes a plain `year_offset` number around and
never changes the bill object; `"does NOT mutate
@bill.introduced_date_time_utc on 404 retry"` pins that.

## Why the 404-retry fake wraps a `StringIO` in `OpenURI::Meta`

`OpenURI::HTTPError.new` wants an `io` that is both a `StringIO` and an
`OpenURI::Meta`. The real `OpenURI` mixes `Meta` into the `io` before
raising, so the fake does the same: it matches the real shape, and the
Steep type checker is satisfied.
