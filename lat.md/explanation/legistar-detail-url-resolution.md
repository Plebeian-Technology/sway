---
lat:
  mode: explanation
---

# Legistar detail URL resolution

Legistar InSite's Gateway endpoint resolves Baltimore City legislative matter identifiers to canonical public detail URLs containing both a record ID and a GUID.

## The disconnect between API identifiers and public URLs

Legistar's public web interface addresses legislation using record numbers and globally unique identifiers that differ entirely from its REST API matter identifiers.

When Sway ingests Baltimore City legislation via Legistar's Web API, the `/v1/baltimore/matters` endpoint returns an integer `MatterId` and a `MatterGuid`. For example, ordinance 26-0217 ("Data Centers Over 5 Megawatts – Moratorium", Sway bill 282) returns `MatterId: 10599` and `MatterGuid: 1EF57441-EAE9-4A5E-8A48-ACA9AC88C5AF`.

However, the public web page hosted at `https://baltimore.legistar.com/LegislationDetail.aspx` requires two query parameters: `ID` and `GUID`. For bill 282 (matter 10599), the working public address is:
`https://baltimore.legistar.com/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570`.

The public web ID (`8135417`) is an internal web database identifier running in the millions, while the API `MatterId` (`10599`) runs in the thousands. Furthermore, the public URL's GUID (`44D47DEC-EC78-4AD0-86B9-B02879001570`) does not match the API's `MatterGuid` (`1EF57441-EAE9-4A5E-8A48-ACA9AC88C5AF`).

Neither parameter can be computed or derived from API data alone. Moreover, Legistar requires both parameters together: requesting `LegislationDetail.aspx` with only `ID` or only `GUID` produces an empty 19-byte error response with HTTP 200 OK. Querying `LegislationSearch.aspx?Search=26-0217` returns HTTP 404.

## Gateway redirection as the reproducible source

The InSite Gateway endpoint acts as an authoritative HTTP redirector mapping matter identifiers to canonical public detail URLs.

Legistar InSite exposes a redirection endpoint at `https://baltimore.legistar.com/Gateway.aspx`. Supplying `M=L` (indicating Legislation matter) and `ID={MatterId}` initiates an HTTP 302 Found redirect whose `Location` header specifies the complete canonical detail path.

Empirical verification against the live Baltimore Legistar host demonstrates the reproducible mapping:
- An HTTP HEAD or GET request to `https://baltimore.legistar.com/Gateway.aspx?M=L&ID=10599` yields HTTP status 302 Found.
- The response `Location` header contains `/LegislationDetail.aspx?ID=8135417&GUID=44D47DEC-EC78-4AD0-86B9-B02879001570`.
- Fetching the resulting destination address returns an authentic HTML document of 119,049 bytes (approximately 119,000 bytes) naming Baltimore ordinance `26-0217` eleven times.

This demonstration proves that `Gateway.aspx?M=L&ID={MatterId}` reliably bridges the gap between stored API matter IDs and public legislation detail URLs without scraping search pages or relying on fragile heuristics.

## Architectural resolution service

The resolution workflow is encapsulated in a dedicated service object that performs redirect resolution with caching and host security validation.

Sway encapsulates this resolution mechanism in `Legistar::DetailUrlResolver` (`app/services/legistar/detail_url_resolver.rb`). The service issues an HTTP HEAD request to `/Gateway.aspx`, parses the HTTP 302 redirect response, and validates that the destination URL points to `LegislationDetail.aspx` on an allowlisted Legistar host.

To minimize latency and network overhead, the resolver caches resolved URLs by matter ID for the lifetime of the resolver instance. If a matter cannot be resolved—because the gateway responds with HTTP 200 or 404, the redirect destination is invalid, or a network failure occurs—the resolver logs a diagnostic warning and returns `nil`.

The resolver incorporates `:head` into its retry methods (`RETRY_METHODS` and `RETRY_OPTIONS`), extending Sway's shared Legistar retry profile so transient 503 responses and network connection drops during Gateway HEAD requests are automatically retried with exponential backoff without altering other Legistar clients' policies.

Under the absent-link architecture documented in [[unlinked-bill-presentation#Unlinked bill presentation]], returning `nil` ensures that unresolvable bills store null in the database rather than a misleading generic search URL, triggering clean fallback presentation across web and mobile readers.

## Ingestion pipeline integration and fallback elimination

During legislation ingestion, the pipeline resolves each matter's public detail URL before database records are created or updated, eliminating generic search fallbacks.

When `FetchBillsService` (`app/services/fetch_bills_service.rb`) processes fetched matters in `#build_metadata`, it invokes `Legistar::DetailUrlResolver` using the matter's numeric identifier. The resulting canonical detail URL is populated in the metadata payload under the `:link` key. If resolution returns nil—because of an unexpected gateway response, a non-redirect status, or a network transport failure—the metadata records `link: nil`.

The refusal rule establishes that a resolution failure on an individual matter is logged and skipped rather than aborting the pipeline run. The good bills continue processing, and the unresolvable bill persists with `link: nil`.

In turn, `LegislationIngestionService` (`app/services/legislation_ingestion_service.rb`) applies the metadata directly to the `Bill` record. Prior to this design, the ingestion service defaulted missing links to `https://baltimore.legistar.com/LegislationSearch.aspx`. Removing this fallback assignment ensures that bills without a resolvable link hold `NULL` in the database. Under the absent-link architecture documented in [[unlinked-bill-presentation#Unlinked bill presentation]], storing null avoids uniqueness collisions and activates clean fallback notices across web and mobile readers without presenting misleading search links.

## Backfill procedure for stored Baltimore bills

A dedicated data migration replaces legacy generic search addresses on stored Baltimore bills with canonical detail URLs or clears them to null.

Historical ingestion runs previously wrote the generic Legistar search address (`https://baltimore.legistar.com/LegislationSearch.aspx`) onto Baltimore bill records whenever a direct link was missing. While newly ingested bills resolve authentic URLs on ingest, pre-existing database rows continued carrying the generic search address, displaying misleading buttons to readers and threatening uniqueness constraint violations.

The data migration (`db/data/20261111000004_resolve_legacy_baltimore_bill_links.rb`) runs the backfill at deploy boot (`rails db:migrate:with_data`) by calling `BaltimoreBillLinkBackfillService.call(raise_on_failure: true)`. For each targeted bill holding the generic search address, the service first checks local cached metadata and then Legistar's API for the numeric matter identifier. When a matter identifier is found, `Legistar::DetailUrlResolver` queries the InSite Gateway endpoint to obtain the canonical `LegislationDetail.aspx` URL containing the authentic record ID and GUID.

When resolution succeeds, the bill is updated with its canonical URL. If the matter cannot be found or gateway resolution returns nil, the bill's link is cleared to `NULL` rather than being left with the generic search address. Under the absent-link architecture documented in [[unlinked-bill-presentation#Unlinked bill presentation]], storing null avoids uniqueness collisions and activates clean fallback notices across web and mobile readers without presenting misleading search links.

Bills already holding canonical detail URLs or null links are untouched on subsequent runs. When an upstream matter lookup encounters an exception, the procedure logs a warning, clears the targeted generic link to `NULL`, and continues processing subsequent rows. If a persistence error occurs, the failure is recorded in `stats[:failed]`, and the service raises `BaltimoreBillLinkBackfillService::PersistenceError`, halting the deploy and guaranteeing that deploy success confirms complete cleanup.
