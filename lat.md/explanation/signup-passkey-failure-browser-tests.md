---
lat:
  mode: explanation
  require-code-mention: true
---

# Signup passkey failure browser tests

Browser examples verify passkey prompt dismissal retry, enrollment callback failure recovery, and unfinished account sign-in routing.

These end-to-end Capybara specs drive Chrome with its virtual authenticator against [[app/controllers/users/webauthn/registration_controller.rb]] and [[app/controllers/users/webauthn/sessions_controller.rb]] to prove users are never stranded when passkey creation fails, callback verification rejects, or sign-in resumes an incomplete account.

## Cancelled passkey prompt retry

Dismissing the browser passkey prompt leaves the SMS code step active so a second confirmation completes enrollment without calling Twilio again.

Using [[spec/support/webauthn_system_helpers.rb#WebauthnSystemHelpers#reject_next_passkey_creation]], Chrome rejects the first `navigator.credentials.create` call with `NotAllowedError`, forcing [[app/frontend/components/auth/PasskeyPanel.tsx#PasskeyPanel]] to show its inline retry notice instead of an error toast. Under production-like rate limits, clicking confirm a second time reuses the verified session in [[app/controllers/phone_verification_controller.rb#PhoneVerificationController#update]] without hitting Twilio again, completes registration through address selection to `/feed`, and keeps passkey start calls within budget.

## Expired registration session callback toast

Posting the registration callback without an active challenge redirects to the Home page with the session-expired alert toast.

If the client reaches [[app/controllers/users/webauthn/registration_controller.rb#RegistrationController#callback]] after phone verification without an active registration challenge in the session, the redirect preserves the verified phone window and flashes the session-expired alert while leaving the phone form enabled on Home.

## Stale challenge verification failure toast

Posting a passkey credential signed for a superseded challenge redirects to the Home page with the verification-failed alert toast.

Requesting a second set of registration options overwrites the server challenge before the browser submits the credential created for the first options, triggering `WebAuthn::Error` verification failure handling, redirecting to Home with `VERIFICATION_FAILED_MESSAGE`, and keeping the verified phone session intact.

## Already registered phone callback toast

When another enrollment attaches a passkey to the phone mid-flow, the callback redirects to Home with the already-registered alert toast.

If a passkey record exists for the verified phone by the time [[app/controllers/users/webauthn/registration_controller.rb#RegistrationController#callback]] runs, the transaction raises `AlreadyRegistered` and redirects to Home with `ALREADY_REGISTERED_MESSAGE` while keeping phone login available.

## Resume enrollment after expired session toast

After an expired-session redirect to Home, re-entering the same phone resumes passkey enrollment without sending another SMS under rate limiting.

Because `session[:verified_phone]` survives the failed callback redirect, submitting the same phone number on Home hits the `"enroll"` resume path in [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#create]] and completes passkey setup to the address form with only the original Twilio verification send.

## Resume enrollment after verification failed toast

After a verification-failed redirect to Home, re-entering the same phone resumes passkey enrollment without sending another SMS under rate limiting.

Keeping the verified phone across `WebAuthn::Error` redirects lets the returning user skip another OTP challenge when retrying on Home and finish creating their passkey to reach the address completion page.

## Unfinished account discoverable sign-in routing

Signing in with a discoverable passkey before finishing address setup routes directly to the address completion form.

Clearing session cookies after passkey enrollment and clicking the discoverable passkey button verifies the assertion in [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#discoverable_callback]] and redirects the incomplete account to `/sway_registration` with the address input visible.

## Unfinished account phone-first sign-in routing

Signing in with a phone number and passkey before finishing address setup routes directly to the address completion form.

Submitting an unfinished account's phone number after clearing cookies triggers the phone-first passkey assertion ceremony in [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#callback]] and lands the user on `/sway_registration` with the address field visible.
