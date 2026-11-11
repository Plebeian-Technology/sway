---
lat:
  mode: explanation
---

# Api::V1::PhoneVerificationsController rate-limit design

Why Api::V1::PhoneVerificationsController's per-phone rate limit also bounds downstream registration spam, and why every phone-keyed rate limiter normalizes the number first.

## Why the per-phone cap also guards registration

`request_code` is rate-limited both per IP (5/hour) and per phone (1/day), sharing a cross-endpoint per-phone counter with web SMS verification.

The 1-per-day per-phone cap does double duty: spamming passkey registration needs a token from `/verify`, so the chain `/verify -> sms_verified_token -> /registrations` inherits the same ceiling as phone verification itself, and sharing the counter across `PhoneVerificationController#create`, `Users::Webauthn::SessionsController#create`, and `Api::V1::PhoneVerificationsController#request_code` prevents bypassing the limit by switching endpoints.

## Why spec/requests/rate_limiting_spec.rb stubs Twilio with a double

The endpoints this spec drives call `send_phone_verification` and `send_email_verification`, which build a real Twilio client out of environment variables.

Without a stand-in, these examples would pass only where the `TWILIO_*` variables happen to be set, and 500 on a bare CI runner with `ArgumentError: sid cannot be nil` from `services(nil)` — an error the controller's `Twilio::REST::RestError` rescue does not catch, since it isn't a `RestError` at all. Swapping in `TwilioDouble` isolates the rate limiting these examples are actually about from that unrelated credential dependency.

## Why every phone-keyed limiter normalizes the number first

`normalize_phone` strips non-digits and drops a leading `"1"`, so every spelling of the same number — `"+1 (area)..."`, `"(area)..."`, `"1-area-..."` — lands in one rate-limit bucket.

An earlier bare `gsub(/\D/, "")` kept a leading `"1"`, so `"+1 (410)..."` and `"410..."` counted as two different numbers, doubling an attacker's per-phone budget. This same normalization is used everywhere a phone number becomes a rate-limit key: `Api::V1::PhoneVerificationsController`, `Api::V1::SessionsController`, and `Users::Webauthn::SessionsController`.

## Why Api::V1::RegistrationsController.create is rate-limited per IP

Answering `409 phone_already_registered` for a number that already has an account doubles as an oracle: without a limit, an attacker could learn which phone numbers are registered on Sway by submitting them one at a time.

The 5-per-IP-per-hour limit (`RateLimitConfig.enabled?(:sign_up)`, shared with `Users::Webauthn::RegistrationController`) is what bounds that. It sat inactive in production until a later change enabled it — the `spec/requests/api/v1/registrations_spec.rb` rate-limiting example ties the limit specifically to the `create` action, so detaching the two fails the test rather than silently going quiet again.

## Why the sign-in challenge throttles two ways

`Api::V1::SessionsController#challenge` is rate-limited both per IP address (10 per 5 minutes) and per phone number (5 per 5 minutes).

`Api::V1::SessionsController#challenge` is rate-limited both per IP address (10 per 5 minutes) and per phone number (5 per 5 minutes) — the web sign-in flow in `Users::Webauthn::SessionsController` uses the same limits, so an attacker gains nothing by switching client.
