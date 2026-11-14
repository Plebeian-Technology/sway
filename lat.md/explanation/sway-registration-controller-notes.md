---
lat:
  mode: explanation
---

# SwayRegistrationController design notes

Design notes for SwayRegistrationController: why one locale's failed lookup is skipped, why the legislator check comes before the service loop, and why mobile gets JSON instead of following the web redirect.

## Why one locale's failed lookup is skipped and reported

An upstream outage never blocks a first registration: `#create` gives each locale its own transaction, so one locale's failure costs only that locale.

An address reaches up to three locales (city, state, Congress), and each resolves through a different upstream: a local boundary file, OpenStates, or Census TIGERweb. Any error from one locale's [[app/services/sway_registration_service.rb#SwayRegistrationService]] call — an unreachable service, a malformed body, a bad roster row — rolls back that locale's own links and leaves the links of the other locales in place. The error is logged as `sway_registration.locale_skipped` and reported to Sentry with the user, address and locale, so nothing is skipped silently.

The user then completes with whatever resolved. The earlier design rolled every locale back and answered `geocoding_unavailable`, which left the user `pending` with a saved address; every retry repeated the failure for as long as the upstream problem lasted, so one bad answer for one locale stopped the whole registration. Each skipped locale is recorded on the user so its representatives can be assigned later ([[registration-dead-ends#A skipped lookup is recorded so it can be retried]]).

Only `StandardError` is caught, and only around one locale's call, so the rest of the action still fails loudly. A registered user switching address takes a different path, which still answers the outage message.

## Why create checks has_user_legislators? before the service loop

`#create` checks [[app/models/user.rb#User#registered?]] before the loop that calls [[app/services/sway_registration_service.rb#SwayRegistrationService]] for each locale, returning early on initial registration or same-address resubmission.

When an already-registered user with an existing [[app/models/user_address.rb#UserAddress]] submits a different address, `#create` requires confirmation and delegates cross-locale reconciliation and [[app/models/user_address_change.rb#UserAddressChange]] auditing to [[app/services/user_address_switch_service.rb#UserAddressSwitchService]]. A first registration has no active link, so the early exit does not fire and every locale goes through the service loop; the locale-parity spec drives that whole loop ([[sway-registration-controller-notes#What AddressScreen.parity.test.tsx deliberately does not cover]]).

## Why mobile gets JSON instead of following the web redirect

Mobile can't follow a redirect into the web Inertia flow — it 500s rendering an Inertia page for a JSON-only request — so `respond_json_or_redirect` gives it JSON instead; web keeps its redirect.

This is decided via `mobile_api_request?` (bearer header OR JSON format), not `request.format.json?` alone, because a bearer client omitting `Accept: application/json` would otherwise fall through to the web redirect.

## What AddressScreen.parity.test.tsx deliberately does not cover

Working out the right `sway_locale_id` happens on the server, inside `SwayRegistrationService`; the mobile app never calculates it.

One server test, `spec/requests/sway_registration_locale_parity_spec.rb`, covers web and mobile at once.

It posts the same address for a pending user once from a cookie session and once with a bearer token, and expects the same set of active representative links from both. The Annapolis, Maryland and Congress locales are seeded from their real rosters, and only the OpenStates and Census HTTP answers are stubbed, so the controller loop, the service, the rosters and the response parsing all run together. The addresses are an Annapolis ward, Towson (Maryland outside any city locale) and Richmond, Virginia (outside every supported state), so a regression in any part shows up as a missing or extra link rather than passing unnoticed. The Baltimore three-locale path and the Census failure path live in the controller spec instead.
