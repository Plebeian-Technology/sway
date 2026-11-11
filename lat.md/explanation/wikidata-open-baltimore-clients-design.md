---
lat:
  mode: explanation
---

# Why Wikidata::Client and OpenBaltimore::Client exist

Both clients replace something that used to be scraped or hand-curated, for the same reason: Legistar, Baltimore's legislative system, does not reliably carry the data.

## Wikidata::Client: reading the sitting mayor

`Wikidata::Client` reads (never writes) the Wikidata Query Service, using SPARQL, its query language. This is where Sway gets Baltimore's current Mayor.

In Wikidata, a city's sitting executive is a "head of government" statement (property P6) on the city's entry, and the current one is the statement with no end date attached (property P582). Baltimore is entry Q5092, so that statement is the Mayor now in office.

Wikidata is used because the Mayor does not appear in Open Baltimore's council-district data and is not reliably kept up to date in Legistar, while an office as prominent as Baltimore's mayoralty is kept current on Wikidata. The Maryland State Archives list of mayors (msa.maryland.gov) would work as a backup, but it is a web page rather than data, so it has not been wired up.

Requests go through `Sway::FaradayStack.wikidata`, which retries failed GETs a limited number of times, asks for JSON results, and sends the descriptive User-Agent that Wikidata's policy for automated clients requires.

## OpenBaltimore::Client: reading council districts

`OpenBaltimore::Client` is a read-only client for the Open Baltimore ArcGIS Feature Service that backs the city's published "Baltimore City Council District" layer.

`OpenBaltimore::Client` is a read-only client for the Open Baltimore ArcGIS Feature Service that backs the city's published "Baltimore City Council District" layer — the live, city-maintained source for the current 14 district council members (name, district, phone, email, council-page URL).

This replaced BOTH the old HTML scrape and the hand-curated `COUNCIL_DISTRICTS_BY_LAST_NAME` map. The city republishes this layer at each election, so the district roster stays up to date with no hand-maintenance. Legistar carries no council district at all, which is why the district source lives here rather than in `Legistar::Client`.

Transport is `Sway::FaradayStack.open_baltimore` (a Faraday connection with bounded GET retries and a 30s timeout). The base URL already carries the ArcGIS org id and services root, so resource paths are relative to it.

### Why the layer id is discovered rather than hardcoded

`#council_district_layer_id` discovers the layer id from the Feature Service root rather than hardcoding it, so a republish that renumbers the layer still resolves. The council-district service exposes exactly one layer.

### Why an ArcGIS error body is checked explicitly

`#get_json` checks for an `{"error": {...}}` body even on an HTTP 200, because ArcGIS reports query errors that way rather than with a non-2xx status.
