---
lat:
  mode: explanation
---

# Census and SwayGeocode implementation notes

Two small historical notes about `lib/census.rb` and `lib/sway_geocode.rb` that don't belong at the call site but are worth keeping somewhere.

## Why CURRENT_CONGRESS_NUMBER is a constant that needs manual bumping

`Census::CURRENT_CONGRESS_NUMBER` is baked into the `outFields` parameter (`CD#{CURRENT_CONGRESS_NUMBER}`) of the Census Bureau TIGERweb URL, so it has to be bumped by hand each new Congress.

`Census::CURRENT_CONGRESS_NUMBER` is baked into the `outFields` parameter (`CD#{CURRENT_CONGRESS_NUMBER}`) of the Census Bureau TIGERweb URL, so it has to be bumped by hand each new Congress: the 119th runs January 2025 to January 2027, so it becomes 120 by January 2027. Bumping it also means confirming the ACS MapServer layer id in `CENSUS_QUERY_URL` still resolves for the new redistricting cycle — the two can drift apart independently.

## Why Census::Congress.data no longer checks for a Hash

`Census::Congress#data` parses the Faraday response body directly.

An older version short-circuited with a `request.is_a?(Hash)` check first. That check could never fire in production — Faraday always returns a `Faraday::Response`, never a `Hash` — and existed only so a test could stub `#request` with a Hash. The Census specs now stub the TIGERweb URL with WebMock, the actual HTTP boundary, so the short-circuit was dead code and was removed.

Several service, job and system specs still stub `#request` with a bare double that answers only `body`. For that reason `#data` reads nothing but the body, and the status and timeout handling lives inside `#request`.

## Why SwayGeocode::Congress and SwayGeocode::Local are plain nested classes

`SwayGeocode.build` is the only module-level method in `lib/sway_geocode.rb`; `Congress` and `Local` are plain nested classes.

They used to sit inside `class << self`, which defined them on the singleton class, so `SwayGeocode::Congress` could not be reached from outside this file — only code inside `build` could see them.

`Congress` also used to `include Census`, which did nothing: `Census` has no instance methods, and `Congress` spells out `Census::Congress` anyway. That include is gone.

## Why ServiceUnavailableError wraps upstream HTTP failures

[[lib/sway_geocode.rb#SwayGeocode#ServiceUnavailableError]] wraps HTTP-layer failures from Census TIGERweb and OpenStates as a transient domain error.

Every malformed Census answer reaches it through one path: [[lib/census.rb#Census#Congress]] raises a `Faraday::Error` subclass, and `SwayGeocode::Congress#districts` already translates any `Faraday::Error`. `#request` raises `Faraday::ServerError` for a non-success status, and Faraday itself raises on a timeout or a refused connection. `#data` raises `Faraday::ParsingError` for a blank body, a body that is not valid JSON, JSON that is not an object, and an object with an `error` key, which is how ArcGIS reports a failed query inside an HTTP 200. Without those checks a parse error escaped as `JSON::ParserError`, and an ArcGIS error object read as an address outside every district, so the House member was lost with no report.

An object with no `features` key, or an empty `features` array, is still a normal answer: the address lies outside every congressional district. The rescue stays limited to `Faraday::Error`, so a programming error still propagates under its own class.

[[lib/census.rb#Census#REQUEST_TIMEOUT_SECONDS]] bounds both the connection and the read. With no timeout, a hung Census server held a registration request for the default Net::HTTP wait of about a minute.

Registration skips and reports a locale whose lookup raises this error: [[sway-registration-controller-notes#Why one locale's failed lookup is skipped and reported]]. The address-switch path and the background registration job's transient retry handle the same class, so a malformed Census answer gets the outage handling there too instead of escaping as a parse error, and district reconciliation reports it under that class.
