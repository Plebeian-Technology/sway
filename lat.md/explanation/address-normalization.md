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

Before trimming, every Unicode space separator becomes an ordinary space and zero-width characters are removed, because text pasted from a web page or map result often carries a non-breaking or zero-width space that would otherwise make `MD` fail to equal `MD` and send the user to no state locale.

## City titleization

City strings are titleized via ActiveSupport, standardising casing across user input while handling multi-word names appropriately.

The city gets the same invisible-space cleanup as the region code first, so a pasted `Baltimore` with a trailing non-breaking space builds the same locale name as a typed one.

## Nominatim address parsing into canonical address attributes

Frontend parsing maps OpenStreetMap Nominatim search response objects into Sway's address structure (`sway.IAddress` with coordinates and region), extracting street components and resolving state names to postal codes.

Nominatim returns granular components such as `house_number`, `road`, `city`/`town`/`village`, and `state`. The parser consolidates road and house number into `street`, extracts standard municipal and postal codes, and resolves region codes to two-letter abbreviations before form submission.

## Defensive coordinate parsing and validation bounds

Latitude and longitude fields from external geocoding payloads are converted to floats and validated within geographic bounds (-90 to 90 for latitude, -180 to 180 for longitude).

Out-of-bounds or non-numeric values are excluded to prevent malformed coordinates from entering registration state.

The server applies the same bounds to a registration submission, because a
client may post typed text or a hand-built body
([[app/controllers/sway_registration_controller.rb#SwayRegistrationController#parsed_coordinate]]).
A value outside them, or one that is not a finite number, is stored as no
coordinate. One bad coordinate drops both, since a lone latitude places nothing.



## United States spellings

`RegionUtil.from_country_code_to_name` reads US, USA, U.S., U.S.A., United States and United States of America, in any case and with surrounding spaces, as the United States.

Clients send the country as free text: the web form sends the Nominatim country name and the mobile app sends the ISO code. Locale names are built from that text, so an unmapped spelling would build a locale such as `baltimore-maryland-usa` that holds no legislators, and the Congress fallback in [[representative-resolution#Congress fallback]] would treat the US state as unknown. Every spelling in [[lib/region_util.rb#RegionUtil#UNITED_STATES_SPELLINGS]] therefore maps to the same name as the code US. Any other country keeps its title-cased text.
