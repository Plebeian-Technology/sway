---
mode: explanation
summary: "Small implementation-history notes for Census::Congress#data and SwayGeocode's class layout, extracted from code comments."
status: agent-extracted
related: [docs/reference/census-tigerweb-response-shape.md]
---

<!-- vale Vale.Spelling = NO -->

# Census and SwayGeocode implementation notes

Two small historical notes about `lib/census.rb` and `lib/sway_geocode.rb`
that don't belong at the call site but are worth keeping somewhere.

## Why CURRENT_CONGRESS_NUMBER is a constant that needs manual bumping

`Census::CURRENT_CONGRESS_NUMBER` is baked into the `outFields` parameter
(`CD#{CURRENT_CONGRESS_NUMBER}`)
of the Census Bureau TIGERweb URL, so it has to be bumped by hand each new
Congress: the 119th runs January 2025 to January 2027, so it becomes 120 by
January 2027. Bumping it also means confirming the ACS MapServer layer id in
`CENSUS_QUERY_URL` still resolves for the new redistricting cycle — the two
can drift apart independently.

## Why `Census::Congress#data` no longer checks for a Hash

`Census::Congress#data` parses the Faraday response body directly. An older
version short-circuited with a `request.is_a?(Hash)` check first. That check
could never fire in production — `Faraday.get` always returns a
`Faraday::Response`, never a `Hash` — and existed only so a test could stub
`#request` with a Hash. Tests now stub `Faraday.get`, the actual HTTP
boundary, instead, so the short-circuit was dead code and was removed.

## Why `SwayGeocode::Congress` and `SwayGeocode::Local` are plain nested classes

`SwayGeocode.build` is the only module-level method in `lib/sway_geocode.rb`;
`Congress` and `Local` are plain nested classes. They used to sit inside
`class << self`, which defined them on the singleton class, so
`SwayGeocode::Congress` could not be reached from outside this file — only
code inside `build` could see them.

`Congress` also used to `include Census`, which did nothing: `Census` has no
instance methods, and `Congress` spells out `Census::Congress` anyway. That
include is gone.
