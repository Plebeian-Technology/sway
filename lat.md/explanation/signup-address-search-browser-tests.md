---
lat:
  mode: explanation
  require-code-mention: true
---

# Signup address search browser tests

Browser tests assert address autocomplete error messaging, recovery, strict-box fallback, and submission when upstream Nominatim lookups fail.

## No results

When address search finds no matching locations, the interface displays a clear message and keeps the form usable without presenting an empty suggestions listbox.

## Upstream failures

Upstream service failures from Nominatim return empty results through the service layer and present the same visible message in the browser.

### Upstream HTTP 429

A rate-limited 429 response from the upstream search service displays the no-results message without a listbox and keeps registration submission active.

### Upstream HTTP 500

A server error response from the upstream search service displays the no-results message without a listbox and keeps registration submission active.

### Upstream timeout

A network timeout on the upstream search service displays the no-results message without a listbox and keeps registration submission active.

## Recovery

Failed search attempts are not cached, allowing subsequent queries with the same text to recover and display suggestions when the upstream service returns results.

## Autocomplete endpoint failure

When the application autocomplete endpoint itself returns an HTTP error, the browser displays an unavailable message until subsequent requests succeed.

## Bounded-locale miss

When a strict bounding-box search for a bounded locale yields no results, the browser automatically retries without the bounding box to locate nearby addresses.

## Edit after select

Editing the input text after selecting an autocomplete suggestion clears previously selected address metadata and submits the edited text directly.
