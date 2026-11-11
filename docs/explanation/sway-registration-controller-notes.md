---
mode: explanation
summary: "Design notes for SwayRegistrationController: the transient-outage message and rollback, why the legislator check comes before the service loop, and why mobile gets JSON instead of following the web redirect."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# `SwayRegistrationController` design notes

## Why geocoding failures roll back and ask for a retry

`REGISTRATION_UNAVAILABLE_MESSAGE` is shown when Census TIGERweb /
OpenStates can't be reached while resolving a user's districts. The
outage is transient, so `#create` rolls back any partial legislator
assignments, leaves the user `pending`, and asks them to retry.

All-or-nothing applies across the three locales (city, state, congress):
if one jurisdiction's geocoding is unreachable, the `UserLegislators`
already created for the others are rolled back too, so the user stays
`pending` (never half-registered) and can retry the whole thing.

## Why `#create` checks `has_user_legislators?` before the service loop

`#create` checks `u.has_user_legislators?` BEFORE the loop that calls
`SwayRegistrationService` for each locale, and returns early when it is
already true. `spec/requests/sway_registration_locale_parity_spec.rb`'s
locale-parity check depends on this ordering: it creates the
`UserLegislator` row up front, faking what a successful service run would
produce, so that once `Address#sway_locales` has been walked the early
exit fires and calls `u.complete!` on the controller's own copy of the
user when the state machine reloads it. Creating the record in the other
order — after the POST — would leave the controller holding a stale
`user` object that never sees the early exit take effect. The fake
service is still stubbed even though the early exit runs first, to keep
real geocoding and other outside calls out of the loop in case the
ordering ever changes.

## Why mobile gets JSON instead of following the web redirect

Mobile can't follow a redirect into the web Inertia flow — it 500s
rendering an Inertia page for a JSON-only request — so
`respond_json_or_redirect` gives it JSON instead; web keeps its redirect.
This is decided via `mobile_api_request?` (bearer header OR JSON format),
not `request.format.json?` alone, because a bearer client omitting
`Accept: application/json` would otherwise fall through to the web
redirect.

## What `AddressScreen.parity.test.tsx` deliberately does not cover

Working out the right `sway_locale_id` happens on the server, inside
`SwayRegistrationService`; the mobile app never calculates it. One server
test, `spec/requests/sway_registration_locale_parity_spec.rb`, covers web
and mobile at once.
