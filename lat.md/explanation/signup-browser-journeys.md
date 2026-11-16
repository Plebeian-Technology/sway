---
lat:
  mode: explanation
  require-code-mention: true
---

# Web sign-up browser journeys

Full browser journeys prove end-to-end user onboarding across all supported jurisdiction tiers.

The web sign-up journey exercises the complete browser boundary: entering a phone number, verifying an SMS confirmation code, generating a passkey with a WebAuthn authenticator, querying address suggestions through debounced Nominatim autocomplete, submitting the address for representative resolution, and following the redirect to the feed.

## Baltimore City sign-up journey

A new user with a Baltimore City address completes verification and discovers their municipal representative.

The Baltimore City onboarding journey exercises boundary resolution against local municipal GeoJSON data without external HTTP requests. Geolocation coordinates map to a city council district, creating the corresponding user-legislator relationship.

### Municipal representative is matched and visible

The registration flow matches city council representation via local boundary data and displays the representative on the index.

After completing registration, the user navigates to the municipal legislators list where the elected representative card and detail link are rendered in the DOM.

## Maryland state sign-up journey

A new user with a non-Baltimore Maryland address completes verification and discovers their state representative.

The Maryland state onboarding journey covers addresses outside municipal charter boundaries, resolving representation via the state legislative API boundary.

### State representative is matched and visible

The registration flow matches state general assembly representation via OpenStates and displays the representative on the index.

After completing registration, the user navigates to the state legislators list where the matched state delegate card and detail link are rendered in the DOM.

## Congressional sign-up journey

A new user with an out-of-state address completes verification and discovers their congressional representative.

The congressional onboarding journey covers addresses outside Maryland entirely, matching federal representation via the Census TIGERweb query boundary.

### Congressional representative is matched and visible

The registration flow matches United States House representation via Census TIGERweb and displays the representative on the index.

After completing registration, the user navigates to the congressional legislators list where the matched federal representative card and detail link are rendered in the DOM.

## Annapolis sign-up journey

A new user with an Annapolis address completes verification and discovers municipal, state, and congressional representation.

The Annapolis onboarding journey exercises boundary resolution against local municipal GeoJSON data for city council wards and the mayor, while concurrently linking state delegates via OpenStates and federal representation via Census TIGERweb.

### City, state, and federal representatives are matched and visible

The registration flow matches Annapolis city officers, Maryland state delegates, and congressional representatives across all three tiers.

After completing registration, the user navigates to the Annapolis city officers list to verify the mayor and ward council representative, followed by the Maryland state and congressional legislators lists to verify cross-tier representation.
