# What kind of place a registered address is

Every address row carries the list of place types Google Places returned for it, so Sway can tell a home from a post office box without asking the person a question they have reason to answer untruthfully.

An address is the evidence that a person belongs in a district, and a
representative acting on Sway's numbers is entitled to expect that the addresses
behind them are places people live. Nothing recorded what kind of place an
address was, so a post office box, an office block and a house were
indistinguishable once stored.

## Why the whole list is stored rather than a verdict

Google returns several types for one place — a flat above a shop can arrive as
`subpremise`, `premise` and `establishment` at once. Storing a boolean would
freeze one reading of that list at the moment it was written.

How Sway weighs those types is a policy that will change: the first version may
accept anything that is not a `post_office`, and a later one may want to treat
an `establishment` in a residential building differently. Keeping the raw list
means changing that policy is a code change, not another migration plus a
backfill over rows whose original evidence has been discarded.

## Why an empty list is not a rejection

The column defaults to an empty list, so every row that predates it reads as
empty, and so does any row created by a path that does not pass place types
through.

An empty list therefore means Sway does not know, which is not the same as
knowing the place is unsuitable. Treating the two alike would reject every
address registered before the column existed.

## Why the web autocomplete's request for types costs nothing extra

Adding `types` to the `fetchFields` call already requesting
`addressComponents` and `location` returns it on the same Place Details
lookup — no extra request, no extra billing.

`useAddressAutocomplete` forwards the returned array untouched through the
same `setData` calls already carrying `region`, `latitude` and `longitude`
onto the registration form, though none of those three is declared on
`sway.IAddress` either. `form.post` submits everything in `form.data`, so
`SwayRegistration.tsx` does not need to name `place_types` for it to reach
the registration endpoint.

## Nominatim place classification and usage constraints

OpenStreetMap Nominatim returns `class`, `type`, and address hierarchy keys rather than Google Places type arrays, allowing Sway to classify places while eliminating commercial API key dependencies.

Nominatim's acceptable use policy limits search requests to a maximum of one request per second, requires result caching for several days, and mandates an identifying Application User-Agent header. Because public OpenStreetMap edge caches omit `Vary: Origin`, direct browser requests risk Same-Origin Policy CORS rejections on cached responses. Browsers also prohibit custom User-Agent headers in client-side fetch requests.

To satisfy upstream policy and eliminate browser CORS blocks, autocomplete queries route through the Rails backend (`GET /addresses/autocomplete` serviced by `NominatimService`). The service queries Nominatim with Faraday using an identifying User-Agent (`Sway/1.0 (civic-tech-app; https://sway.vote)`), caches responses in `Rails.cache` for 24 hours, and applies client debounce and controller-level rate limiting (60 requests per minute).


## Nominatim address payload mapping

[[app/frontend/sway_utils/parseNominatimAddress.ts#parseNominatimAddress]] maps OpenStreetMap Nominatim search responses into Sway's address structure.

Nominatim returns address components across structured properties (`house_number`, `road`, `city`, `state`, `country`, `postcode`) while supplying coordinates in top-level `lat` and `lon` fields. The parser converts coordinates to floating-point numbers and resolves standardized state abbreviations so downstream registration geocoding and district lookups remain consistent.
