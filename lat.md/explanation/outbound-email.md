---
lat:
  mode: explanation
---

# Outbound email

Production delivers mail through Resend's HTTP API, configured in
`config/environments/production.rb` and credentialed in
`config/initializers/resend.rb`.

## Delivery goes over HTTPS, not SMTP

The `resend` gem's railtie registers `:resend` as an ActionMailer delivery
method, so `config.action_mailer.delivery_method = :resend` replaces an entire
`smtp_settings` block and every mailer keeps working untouched.

Mail does not go over an SMTP relay. A mailbox that carries a handful of
messages a year does not justify a paid relay tier.

The second reason is diagnostic. SMTP reports failure badly. An exhausted
account may not answer `535`; it can negotiate STARTTLS and then drop the
connection during AUTH, which is indistinguishable from a revoked key, a wrong
username, or a network fault. An HTTP call returns a status and a JSON body
naming the cause.

## The preview is built from the object the mailer renders

The "email your legislator" preview is assembled on the server from
`LegislatorEmailText`, the same object the mailer itself renders.

Building the preview from anything else would make it a second implementation
of the message, free to drift from what is actually sent. Sharing the object
means what the reader approves is what leaves the machine.

When a bill has no valid source URL, `LegislatorEmailText` terminates the
sentence cleanly at the title and omits the introductory clause. The HTML and
plain-text mailer templates suppress the anchor tag and URL interpolation,
ensuring absent-source rendering produces a complete sentence without route
generation errors, dangling punctuation, or preview drift.

## A trailing newline reads as a revoked key

A stray newline on the key is invisible in every log and fails only at the point
of sending.

`kamal env push` reads secrets from a file, and a file ordinarily ends in a
newline. The old SMTP path base64-encoded that whitespace verbatim into AUTH
PLAIN and SendGrid answered `535`; an HTTP `Authorization` header carries it
just as faithfully. `ENV["RESEND_EMAIL_API_KEY"].to_s.strip.presence` strips it
inline rather than going through `EnvSecret`, matching how `fcm.rb` and
`sentry.rb` read their own credentials, because an initializer that names an
autoloaded constant ties boot order to the reloader for no gain.

`presence` matters as much as `strip`. A key that is present but blank would let
`Resend.api_key` hold an empty string, and the gem checks only that the key is
set — an empty one would reach the API and be refused there rather than at boot.

## A failed delivery is visible only to the error reporter

A delivery that fails raises inside the job container, where nothing the user
did is waiting on it.

`deliver_later` enqueues and returns successfully whatever happens afterwards,
so the request that triggered the mail reports no problem. The exception reaches
only the job's log, Solid Queue's failed-execution record, and Sentry at
`SENTRY_DSN`. Sway raises no alert of its own for a failed delivery, so when
`SENTRY_DSN` is unset or its collector is unreachable from the production host,
mail failures are silent end to end — a lapsed or revoked provider key shows up
as missing mail, not as an error anyone is told about.

## Why mailers default to outreach@sway.vote and bake invite expiry into signed tokens

[[app/mailers/application_mailer.rb#ApplicationMailer]] and [[app/mailers/user_legislator_email_mailer.rb#UserLegislatorEmailMailer]] default their sender address to `outreach@sway.vote` so outbound messages use the verified production sender domain rather than a placeholder address.

For organization invites, [[app/mailers/user_organization_membership_invite_mailer.rb#UserOrganizationMembershipInviteMailer]] bakes `expires_at` into `signed_id` at send time so extending an invite requires regenerating and resending the token, while [[app/serializers/user_legislator_email_resource.rb#UserLegislatorEmailResource]] exposes only delivery status and legislator identity without internal send-tracking columns.
