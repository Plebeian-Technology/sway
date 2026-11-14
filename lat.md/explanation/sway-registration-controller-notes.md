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

When an already-registered user with an existing [[app/models/user_address.rb#UserAddress]] submits a different address, `#create` requires confirmation and delegates cross-locale reconciliation and [[app/models/user_address_change.rb#UserAddressChange]] auditing to [[app/services/user_address_switch_service.rb#UserAddressSwitchService]]. `spec/requests/sway_registration_locale_parity_spec.rb`'s locale-parity check depends on this ordering: it creates the `UserLegislator` row up front on a user without a prior `UserAddress`, faking what a successful service run would produce, so that once `Address#sway_locales` has been walked the early exit fires and calls `u.complete!` on the controller's own copy of the user when the state machine reloads it. Creating the record in the other order — after the POST — would leave the controller holding a stale `user` object that never sees the early exit take effect. The fake service is still stubbed even though the early exit runs first, to keep real geocoding and other outside calls out of the loop in case the ordering ever changes.

## Why mobile gets JSON instead of following the web redirect

Mobile can't follow a redirect into the web Inertia flow — it 500s rendering an Inertia page for a JSON-only request — so `respond_json_or_redirect` gives it JSON instead; web keeps its redirect.

This is decided via `mobile_api_request?` (bearer header OR JSON format), not `request.format.json?` alone, because a bearer client omitting `Accept: application/json` would otherwise fall through to the web redirect.

## What AddressScreen.parity.test.tsx deliberately does not cover

Working out the right `sway_locale_id` happens on the server, inside `SwayRegistrationService`; the mobile app never calculates it.

One server test, `spec/requests/sway_registration_locale_parity_spec.rb`, covers web and mobile at once.
