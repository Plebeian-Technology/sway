---
lat:
  mode: explanation
  require-code-mention: true
---

# Signup registration failure browser tests

Browser tests verify registration failure paths, outage fallbacks, unresolvable seats, unlocated addresses, and recovery behaviors during account onboarding.

The browser suite exercises submit failure paths in [[app/controllers/sway_registration_controller.rb#SwayRegistrationController#create]] and [[app/frontend/pages/SwayRegistration.tsx#SwayRegistration]], verifying that lookup failures, malformed upstream responses, unseated officers, unlocated addresses, network errors, double submits, and expired sessions complete or recover gracefully without unhandled error dialogs.

## Submit without a selection

Submitting an address that cannot be placed leaves the record unlocated, prompts the user to add a city or ZIP, and permits continuing to the feed.

When a user types an address without selecting a suggestion and the geocoder returns no coordinates, the server records the address as unlocated, assigns the President in Congress US0 as a fallback, records Congress as pending, and responds with a prompt asking for city, state, or ZIP. The browser displays the unlocated notice along with a continue link that routes to the feed.

## Census outage

Failures in upstream Census boundary queries skip House district assignment while assigning state senators and leaving the user registration completed.

### HTTP 502 gateway error

An upstream HTTP 502 gateway error from the Census TIGERweb API completes registration with state senators and skips House member assignment without an outage message.

When the Census geocoding endpoint returns a gateway error, the registration service catches the error, logs a warning, skips the congressional district, and assigns state senators in district 0. The user completes registration and lands on the feed without an error notice.

### Empty body response

An upstream HTTP 200 response with an empty body from the Census TIGERweb API completes registration with state senators and skips House member assignment.

When Census returns an empty body, the Faraday parser raises a parsing error that the service translates into a skipped district lookup, completing registration with state senators while deferring House member assignment.

### Error JSON payload

An upstream HTTP 200 response returning an ArcGIS error JSON payload from Census TIGERweb completes registration with state senators and skips House assignment.

When Census returns a 200 response carrying an ArcGIS error structure, the parser treats it as an outage, skipping the House seat while assigning state senators and completing registration cleanly.

## Unresolvable seat

A current term lacking a persisted seat identity in a configured locale-wide office skips the unseated officer while completing registration with seated representatives.

When a locale-wide office contains an unseated current term alongside seated representatives, the service skips the unseated term with a warning, assigns the seated officers, and completes registration without error dialogs.

## Address with no supported Sway locale

An address located in an unsupported jurisdiction completes registration with the state delegation and district representative in Congress without missing-representative errors.

When an address is submitted in a state outside supported city or state jurisdictions, the registration service skips local assignments and resolves the state's senators and congressional district representative in Congress.

## Non-US address

An international address outside the United States completes registration and resolves the seated President term in the Congress locale-wide district as its sole representative.

When an address is located outside the United States, representative lookup skips regional and congressional districts and assigns the seated President term in US0 as the user's sole active representative.

## Generic request failure

A network-level request failure during registration form submission presents an inline error notification and preserves entered address fields for retry.

When an XMLHttpRequest network failure interrupts the registration submission, the browser catches the network error, displays an error notification, and leaves the address form interactive for resubmission.

## Double submit

Submitting the registration form twice in rapid succession completes onboarding cleanly, creating exactly one address link and preventing duplicate representative assignments.

When multiple submit events trigger concurrently, the client cancels redundant requests and the server handles concurrent creation cleanly, ensuring exactly one address record and no duplicated representative links.

## Expired session

Submitting registration after browser session expiration redirects the unauthenticated client to the landing page with authentication prompts and without unhandled errors.

When cookies are cleared before submitting the address form, the server rejects the unauthenticated request with a redirect to the home page, where the client sees authentication options and no raw error dialog.
