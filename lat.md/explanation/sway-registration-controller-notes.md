---
lat:
  mode: explanation
---

# SwayRegistrationController design notes

Design notes for SwayRegistrationController: the transient-outage message and rollback, why the legislator check comes before the service loop, and why mobile gets JSON instead of following the web redirect.

## Why geocoding failures roll back and ask for a retry

`REGISTRATION_UNAVAILABLE_MESSAGE` is shown when Census TIGERweb / OpenStates can't be reached while resolving a user's districts.

The outage is transient, so `#create` rolls back any partial legislator assignments, leaves the user `pending`, and asks them to retry.

All-or-nothing applies across the three locales (city, state, congress): if one jurisdiction's geocoding is unreachable, the `UserLegislators` already created for the others are rolled back too, so the user stays `pending` (never half-registered) and can retry the whole thing.

## Why create checks has_user_legislators? before the service loop

`#create` checks [[app/models/user.rb#User#registered?]] before the loop that calls [[app/services/sway_registration_service.rb#SwayRegistrationService]] for each locale, returning early on initial registration or same-address resubmission.

When an already-registered user with an existing [[app/models/user_address.rb#UserAddress]] submits a different address, `#create` requires confirmation and delegates cross-locale reconciliation and [[app/models/user_address_change.rb#UserAddressChange]] auditing to [[app/services/user_address_switch_service.rb#UserAddressSwitchService]]. `spec/requests/sway_registration_locale_parity_spec.rb`'s locale-parity check depends on this ordering: it creates the `UserLegislator` row up front on a user without a prior `UserAddress`, faking what a successful service run would produce, so that once `Address#sway_locales` has been walked the early exit fires and calls `u.complete!` on the controller's own copy of the user when the state machine reloads it. Creating the record in the other order — after the POST — would leave the controller holding a stale `user` object that never sees the early exit take effect. The fake service is still stubbed even though the early exit runs first, to keep real geocoding and other outside calls out of the loop in case the ordering ever changes.

## Why mobile gets JSON instead of following the web redirect

Mobile can't follow a redirect into the web Inertia flow — it 500s rendering an Inertia page for a JSON-only request — so `respond_json_or_redirect` gives it JSON instead; web keeps its redirect.

This is decided via `mobile_api_request?` (bearer header OR JSON format), not `request.format.json?` alone, because a bearer client omitting `Accept: application/json` would otherwise fall through to the web redirect.

## What AddressScreen.parity.test.tsx deliberately does not cover

Working out the right `sway_locale_id` happens on the server, inside `SwayRegistrationService`; the mobile app never calculates it.

One server test, `spec/requests/sway_registration_locale_parity_spec.rb`, covers web and mobile at once.
