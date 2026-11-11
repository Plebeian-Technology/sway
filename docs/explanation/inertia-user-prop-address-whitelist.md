---
mode: explanation
summary: "Why the shared user prop (web inertia_share and mobile bootstrap) ships Address#to_sway_json instead of the raw ActiveRecord attributes hash."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the shared user prop ships `Address#to_sway_json`, not raw attributes

Both `ApplicationController`'s `inertia_share` `user` prop and
`Api::V1::BootstrapController`'s `current_user` payload build the address
through `Address#to_sway_json` — a whitelist of fields — rather than the raw
ActiveRecord attributes hash.

The raw attributes hash carries `latitude`/`longitude` at full precision
(about 11cm) and the `street3` field the web UI trims. Shipping it would
put the user's home coordinates into Inertia's `window.history.state`,
readable by anything with access to the browser's history, and would leak
`street3` to callers that never asked for it. `Address#to_sway_json` keeps
latitude/longitude server-side and matches the fields web actually shows.

`Api::V1::BootstrapController` mirrors `ApplicationController`'s
`inertia_share` shape for this reason, so mobile sees the same JSON shape
web does and inherits the same leak protection.

## Why `TParsedGoogleAddress` carries latitude/longitude but `sway.IAddress` does not

Google calls the state `"administrative_area_level_1"`, and the registration
form's data carries a `"region"` key that `sway.IAddress` does not have (it
only has `region_code`), so `app/frontend/sway_utils/parseGoogleAddressComponents.ts`
adds its own input shape, `TParsedGoogleAddress`. `latitude` and `longitude`
stay on this INPUT shape because the form posts them to the server for
geocoding, but they are deliberately left out of the shared `sway.IAddress`
payload: coordinates must never end up in the browser's saved history state.

`parseGoogleAddressComponents` boils a Google Places result — from
`PlacePrediction.toPlace().fetchFields` asking for `"addressComponents"` and
`"location"` — down to the address fields the registration form fills in. A
`Place` only carries the parts Google actually returned, so anything missing
is left out and a partial match never wipes a value the person already
typed.
