---
mode: explanation
summary: "Why every Twilio::REST::RestError rescue across the codebase logs only safe fields (phone_last4, twilio_code) instead of the exception itself."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why Twilio error handling logs only safe fields

Every place in this codebase that rescues `Twilio::REST::RestError` — SMS
send/verify in `Api::V1::PhoneVerificationsController`,
`PhoneVerificationController`, the shared `Authentication` concern, and
email verification in `Users::EmailVerificationsController` and
`Users::PasskeysController` — logs only safe fields
(`phone_last4`/an address fragment, `twilio_code`) rather than the
exception itself.

Twilio's own error message embeds the recipient's phone number (or email
address, for the SendGrid-backed email path). Both the app's logger — which
prints the whole chain of causes — and Sentry would put that personal data
on the record if the raw exception were logged or re-raised without care.
Sanitized wrappers are raised and reported in place of Twilio's own error,
so the personal data never becomes the `.cause` of anything the logger
walks.

## Why `send_email_verification` doesn't touch the session

`Authentication#send_email_verification` uses the same clean error handling
as `send_phone_verification`, because Twilio's error message contains the
recipient's address too. Unlike the phone path, it does NOT touch the
session — the caller owns `session[:pending_email]`.

## Why `verification_approved?` catches nothing

`Authentication#verification_approved?` is a shared code check for
`PhoneVerificationController` (web) and
`Api::V1::PhoneVerificationsController` (mobile). It deliberately catches
nothing — the two callers handle Twilio errors differently (web redirects
on "not found"/20404 and re-raises anything else; mobile returns false).
It also checks emailed codes, since `to:` may be a phone or an email
address.

## Why `SmsDeliveryJob` raises its sanitized error outside the rescue block

`SmsDeliveryJob` needs a failed SMS to retry with bounded backoff, not be
silently swallowed. But a Twilio `RestError` MESSAGE embeds the
recipient's phone number (e.g. error 21211: "The 'To' number +1... is not
a valid phone number."). Retrying on the raw `RestError` would route that
message through `ApplicationJob#job_fail` -> `SwayLogging.log_exception`,
which redacts only Anthropic keys — printing the phone number in
plaintext on every attempt (the same kind of leak already closed for job
arguments). So it rescues the `RestError`, logs only the safe numeric
code/status, and retries on a sanitized `DeliveryError`, which carries no
personal data. The `{to:, body:}` job arguments are still redacted by
`SwayLogging.summarize`.

`DeliveryError` is raised OUTSIDE the rescue block on purpose: raising
inside it would attach the phone-bearing `RestError` as this error's
`cause`, and `SwayLogging.log_exception` logs the full cause chain. Out
here Ruby's `$!` (the "current exception") is nil, so `DeliveryError`
carries no cause — and no personal data — into `job_fail`'s
`log_exception`.

### Why the `TWILIO_FROM_PHONE` blank check has a known gap

`TWILIO_FROM_PHONE` is the only one of the four Twilio env vars read
outside `Sway::TwilioClient`. The `blank?` check catches a
whitespace-only value but NOT a real number with a trailing newline —
Twilio rejects that as `RestError` 21212, which gets logged as
`code=`/`status=` only (naming no env var) and retried through all three
attempts even though it can never succeed.

## Why `VotingReminderJob`'s inner rescue logs only structured fields and the error class

`VotingReminderJob`'s per-user rescue wraps
`SmsNotificationService.send_voting_reminder`, so the caught error may be a
Twilio error whose `#message` embeds the recipient's phone number. It is
NOT handed to `log_exception` (which dumps the raw message + backtrace);
instead it logs structured fields and the error CLASS only. The backtrace
is logged separately, and only in a local environment.

The job's OUTER rescue is safe to hand to `log_exception`'s full-chain
dump: per-user SMS errors are caught by the inner rescue, so the outer
path only sees job-level (query/database/framework) failures, which carry
no personal data.

## Why `PhoneVerificationController#update` reads `e.full_message` only to branch

The rescue in `PhoneVerificationController#update` reads
`e.full_message` solely to decide whether Twilio reported a "not found"
verification (code `20404`) — it is never logged or re-raised, because
`full_message` can contain the recipient's phone number. Only the numeric
`code`/`status_code` are logged or folded into the sanitized
`Authentication::TwilioVerificationError`, which is raised after the
rescue block ends so Ruby does not attach the raw `RestError` (and the
phone number inside it) as `.cause`.

## Why `#update` doesn't create a user on a verified phone

`PhoneVerificationController#update` deliberately does not create a user
record once a phone is verified. Doing so would open a race where an
attacker registers a passkey on another device using the now-verified
phone before the legitimate user completes signup. The verified phone is
held in `session[:verified_phone]` instead, and user creation happens
later in the registration flow.

## Why Sway::TwilioClient centralizes the Twilio::REST::Client build

`Sway::TwilioClient` is the one place the Twilio REST client is built. It
reads the same `TWILIO_ACCOUNT_SID`/`TWILIO_AUTH_TOKEN` credentials that
its three callers (`SmsDeliveryJob`, `OnDeactivatedPhoneDeleteUserJob`, and
the `Authentication` concern's `#twilio_client`) used to read with inline
`Twilio::REST::Client.new(...)` calls, so existing Twilio test stubs
(`allow(Twilio::REST::Client).to receive(:new)`) still intercept.

Both values are sent as HTTP Basic credentials, so a stray trailing
newline in either one causes a 401 that looks exactly like an expired
token — the same `EnvSecret`/newline failure mode covered in
[env-secret-blank-value-handling.md](env-secret-blank-value-handling.md).

## Testing that the browser never shows the phone number

`spec/system/phone_verification_error_spec.rb` checks what the browser
really shows when a Twilio error fires, not just what the server logs:
the failure message appears and the phone number appears nowhere in the
page text. The confirm-code request is a background JSON call, so the
controller's redirect-with-a-flash-message is swallowed when the browser
follows the redirect; what the user sees instead is one of the generic
error toasts. The point of the check is that regardless of which toast
shows, the sign-in does not move forward and no phone digits appear
anywhere on the page.

The example builds its Twilio error with `Twilio::REST::RestError.allocate`
plus stubbed `message`/`full_message`, matching Twilio's real shape: a
message that embeds the recipient's phone number, exactly the thing that
used to leak onto the page.

## Why the session guard checks for `nil`, not `blank?`

`send_phone_verification` guards with `session.nil? || phone_.blank?`
rather than checking `session.blank?`. A fresh
`ActionDispatch::Request::Session` reports `empty?` (and therefore
`present?` is false) on a first-time visitor, even though the session
object itself is valid — so a blank-style check would incorrectly treat a
brand-new, working session as unusable.
