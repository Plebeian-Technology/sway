---
mode: explanation
summary: "Why Sway needs an inbound Twilio SMS webhook to sync users.sms_notifications_enabled even though Twilio Advanced Opt-Out already blocks delivery at the carrier."
status: authored
related: [docs/explanation/twilio-error-phone-redaction.md, docs/explanation/sms-consent-copy-verbatim.md]
---
<!-- vale Vale.Spelling = NO -->

# Why the app needs an inbound STOP/START webhook

Twilio's Advanced Opt-Out feature answers an inbound `STOP` text itself and
blocks further delivery at Twilio's end — Sway is already carrier-compliant
without any code here. But before this webhook existed, Sway never learned
about that opt-out: `users.sms_notifications_enabled` stayed `true` for a
user who had texted STOP. That was not a delivery problem (Twilio silently
dropped the messages), it was a state problem — the notifications settings
panel kept showing that user a green "Enabled" badge, and every SMS-sending
service kept enqueuing `SmsDeliveryJob` work that could never arrive.
`Webhooks::TwilioMessagesController` and `SmsOptOutService` exist to close
that gap by keeping the `users` row in sync with what Twilio already
enforces, not to add opt-out enforcement of Sway's own.

## Why the response carries no TwiML body

Twilio's Advanced Opt-Out already replies to the user for both STOP and
START keywords. Returning a TwiML `<Response><Message>...` body from this
controller would generate a second, duplicate reply. `create` always ends
with `head :no_content` on the success and no-op paths — never a body.

## Why the spec computes a real signature instead of stubbing the validator

`spec/requests/webhooks/twilio_messages_spec.rb` builds the
`X-Twilio-Signature` header it sends by implementing Twilio's documented
algorithm directly — sort the POST parameters by key, append each key
immediately followed by its value to the full request URL, HMAC-SHA1 the
result with the auth token, Base64-encode it.

Two things were rejected. Stubbing
`Twilio::Security::RequestValidator#validate` to return `true`/`false` only
proves the controller branches on whatever the stub says; the stub never
looks at the `url` or `params` arguments, so a controller passing the wrong
ones still passes. Calling the gem's own private `build_signature_for` fixes
that but leaves the test circular: signing and verifying with the same
object would agree even if both were wrong in the same way, and it couples
the suite to an undocumented method name.

Implementing the algorithm in the spec means the passing tests assert
interoperability with Twilio's published specification rather than with this
gem's opinion of it. It also pins the controller's arguments: replacing
`request.original_url` with any other URL fails 16 of the 20 examples.

## The signature/URL proxy caveat — check this first if signatures start rejecting

`Twilio::Security::RequestValidator#validate` recomputes the signature over
the exact URL Twilio itself requested and compares it to the
`X-Twilio-Signature` header. The controller builds that URL from
`request.original_url`. In production this app sits behind Caddy and a
Cloudflare tunnel; in dev behind Caddy plus the `dev_cloudflared` tunnel at
`https://<dev-tunnel-host>`. If Rails reconstructs a different scheme or host
than what Twilio actually requested — for example `http://` instead of
`https://`, because a proxy hop didn't forward `X-Forwarded-Proto` — every
signature check fails and every inbound STOP/START is rejected with 403.
That mismatch is the first thing to check before assuming the shared auth
token is wrong: compare `request.original_url` (log it once, without any
other request data) against the URL configured in the Twilio console for
this number's messaging webhook.

## Why the auth-token-blank path returns 503 instead of skipping verification

If `TWILIO_AUTH_TOKEN` is blank, `Twilio::Security::RequestValidator.new`
would build a validator with no secret, and any signature (including no
signature at all) would either fail loudly or, worse, be trivially
forgeable. The controller checks for a blank token before constructing the
validator and returns 503 without touching the database — a blank token
must never be treated as "verification not required."

## Why an unknown phone number returns success, not an error

Twilio does not tell the app in advance which phone numbers belong to a
Sway account, and Sway's `phone` column does not always have an active
opt-in row for every number that could ever text a Sway-owned Twilio
number (wrong numbers, numbers no longer tied to an account, numbers from
before Sway existed). `SmsOptOutService#call` looks the user up and simply
returns when none is found. The controller always answers `204 No Content`
whether or not a matching user existed, because from Twilio's perspective
the webhook was still handled correctly — there is nothing for Sway to
retry.

## Why the flag write skips validations and callbacks

`User` has a `before_create` callback that force-resets several boolean
columns (including `sms_notifications_enabled`) on creation, and
validations (`phone` presence/uniqueness/length, `email` uniqueness,
`full_name` format, `theme_mode` inclusion) that run on every `save`/
`update!`. This webhook is flipping one column on an *existing* row it
found by phone lookup — running those validations again risks a save
failing on unrelated, pre-existing data problems on that row (a bad
`full_name`, a stale `theme_mode`) that have nothing to do with SMS opt-out.
A user who texts STOP must always be recorded as having texted STOP; a
validation failure elsewhere on their record must not be able to swallow
that.

The write is `update_columns(sms_notifications_enabled: value, updated_at:
Time.current)` rather than `update_column`, which would leave `updated_at`
untouched. Bumping it explicitly matches how this model already writes
columns directly elsewhere — `User#cascade_org_pref_off!` uses
`organization_follows.update_all(column => false, :updated_at =>
Time.current)` for the same reason. Nothing currently keys a cache or a
sync cursor off `users.updated_at`, so this is not fixing a live bug; it
keeps the row's modification time honest so that a future cache key, ETag
or incremental-sync query cannot silently miss an opt-out.
