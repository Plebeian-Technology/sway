---
lat:
  mode: explanation
---

# Api::V1::PhoneVerificationsController rate-limit design

Why a one-time code request has no per-phone daily cap, what bounds registration spam instead, and why every phone-keyed rate limiter normalizes the number first.

## Why a one-time code has no per-phone daily cap

A one-time code request has three send paths, and none has a per-phone daily cap. Each is limited per IP: [[app/controllers/phone_verification_controller.rb#PhoneVerificationController#create]] (web) and [[app/controllers/api/v1/phone_verifications_controller.rb#PhoneVerificationsController#request_code]] (mobile), and [[app/controllers/users/webauthn/sessions_controller.rb#SessionsController#create]] (web sign-up).

The web send allows 10 per hour per IP and the mobile send 5 per hour per IP, both behind the `:phone_verify` kill switch. The sign-up send is the main web path. It uses the sign-in limiters instead: 10 per 5 minutes per IP and 5 per 5 minutes per phone, behind the `:sign_in` kill switch. A blocked user is told to wait for the blocking limiter's whole window, sent as `Retry-After` and worded by the web client as minutes or "about an hour", because the rate-limit store cannot say how much of the window is left, so the window is the honest upper bound; every other limiter keeps the one-minute default of [[app/controllers/concerns/rate_limit_responder.rb#RateLimitResponder#render_rate_limited]].

A one-time code goes through Twilio Verify, a separate API from SMS send, so the operator decided it does not count against a per-phone daily SMS limit. The earlier cap of one code per phone per day locked out any new user who cancelled the passkey prompt, reloaded the page, or never received the first text: no second code could arrive for up to 24 hours, so sign-up could not finish that day. `Users::Webauthn::SessionsController#create`, which sends the code for a new user's phone-first sign-up, has no per-phone daily cap either.

Registration spam needs a verified code, and a verified code needs a code request, so the chain `/verify -> sms_verified_token -> /registrations` is bounded by the per-IP code-request limits, the sign-in limiters on the phone-first path, the per-IP registration-start limits, and Twilio Verify's own limits on a phone number. Code checks keep their per-phone limit (5 per 10 minutes), which bounds guessing a code rather than sending one.

## Why spec/requests/rate_limiting_spec.rb stubs Twilio with a double

The endpoints this spec drives call `send_phone_verification` and `send_email_verification`, which build a real Twilio client out of environment variables.

Without a stand-in, these examples would pass only where the `TWILIO_*` variables happen to be set. On a bare CI runner the Verify service id is missing, and every send and check answers the handled outage reply described in [[twilio-error-phone-redaction#Why a missing Verify service id is answered like an outage]] instead of reaching the rate limiter. `TwilioDouble` sets a placeholder service id and stubs the client, which isolates the rate limiting these examples are actually about from that unrelated credential dependency.

## Why every phone-keyed limiter normalizes the number first

`normalize_phone` strips non-digits and drops a leading `"1"`, so every spelling of the same number — `"+1 (area)..."`, `"(area)..."`, `"1-area-..."` — lands in one rate-limit bucket.

An earlier bare `gsub(/\D/, "")` kept a leading `"1"`, so `"+1 (410)..."` and `"410..."` counted as two different numbers, doubling an attacker's per-phone budget. This same normalization is used everywhere a phone number becomes a rate-limit key: `Api::V1::PhoneVerificationsController`, `Api::V1::SessionsController`, and `Users::Webauthn::SessionsController`.

## Why Api::V1::RegistrationsController.create is rate-limited per IP

Answering `409 phone_already_registered` for a number that already has an account doubles as an oracle: without a limit, an attacker could learn which phone numbers are registered on Sway by submitting them one at a time.

The 5-per-IP-per-hour limit (`RateLimitConfig.enabled?(:sign_up)`) is what bounds that. It sat inactive in production until a later change enabled it — the `spec/requests/api/v1/registrations_spec.rb` rate-limiting example ties the limit specifically to the `create` action, so detaching the two fails the test rather than silently going quiet again.

The web enrollment start, `Users::Webauthn::RegistrationController#create`, shares the kill switch but is keyed on the session's verified phone, 20 starts an hour, with the client IP as the key only when the session has no verified phone. The 409 answer needs a verified phone, so a limit per verified phone still bounds the oracle, while many people behind one carrier, café or event network can all start enrollment, and one person's cancelled passkey prompts no longer use up a shared IP's allowance. A refused start sends `Retry-After: 3600`. The limiter carries its own name, because Rails builds an unnamed limiter's cache key from the controller and the key value alone, which would share one counter with the application-wide per-IP limiter and count each request twice.

## Why the sign-in challenge throttles two ways

`Api::V1::SessionsController#challenge` is rate-limited both per IP address (10 per 5 minutes) and per phone number (5 per 5 minutes).

`Api::V1::SessionsController#challenge` is rate-limited both per IP address (10 per 5 minutes) and per phone number (5 per 5 minutes) — the web sign-in flow in `Users::Webauthn::SessionsController` uses the same limits, so an attacker gains nothing by switching client.
