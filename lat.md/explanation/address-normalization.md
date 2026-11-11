---
lat:
  mode: explanation
---
# Address normalization

Address normalization standardises region codes and city names before validation so downstream geocoding and locale lookups receive canonical values.

## Why normalization runs before validation

Address normalization executes during ActiveRecord's `before_validation` callback rather than `after_initialize`. This ensures dirty tracking functions as expected and eliminates CPU overhead when reading existing records from storage.

## Region code resolution and casing

Full state and territory names are resolved to two-letter uppercase postal abbreviations through `RegionUtil`. Input that is already two letters is upcased directly, and unrecognized state names are retained and upcased without raising errors.

## City titleization

City strings are titleized via ActiveSupport, standardising casing across user input while handling multi-word names appropriately.

## Nominatim address parsing into canonical address attributes

Frontend parsing maps OpenStreetMap Nominatim search response objects into Sway's address structure (`sway.IAddress` with coordinates and region), extracting street components and resolving state names to postal codes.

Nominatim returns granular components such as `house_number`, `road`, `city`/`town`/`village`, and `state`. The parser consolidates road and house number into `street`, extracts standard municipal and postal codes, and resolves region codes to two-letter abbreviations before form submission.

## Defensive coordinate parsing and validation bounds

Latitude and longitude fields from external geocoding payloads are converted to floats and validated within geographic bounds (-90 to 90 for latitude, -180 to 180 for longitude).

Out-of-bounds or non-numeric values are excluded to prevent malformed coordinates from entering registration state.


