---
mode: explanation
summary: "Explains why PushNotificationSubscription#to_builder withholds auth/p256dh, and why the VAPID key pair must never carry a trailing newline."
status: agent-extracted
related: [docs/explanation/api-key-hmac-secret-handling.md]
---
<!-- vale Vale.Spelling = NO -->

# PushNotificationSubscription design notes

## Why to_builder withholds auth and p256dh

`PushNotificationSubscription#to_builder` sends only `id`, `endpoint`,
`subscribed`, and `created_at` — never `auth` or `p256dh`. Those two
columns are the secret keys the server uses to encrypt push messages to a
device; anyone holding `endpoint`, `auth`, and `p256dh` together can push
arbitrary messages to that device. The Notifications page only needs to
match on `endpoint` to find the row for the device in hand, and reads
`subscribed` to draw its toggle — it never needs the encryption secrets
themselves.

## Why the VAPID keys must never carry a trailing newline

`#vapid` reads `VAPID_PUBLIC_KEY` and `VAPID_PRIVATE_KEY` as base64url
text. A trailing newline on either decodes into different bytes than the
key material itself, and the push service then turns Sway's signed token
away as unauthorized — the same newline-in-a-secret failure mode
`ApiKey.hmac_secret_key` guards against for its own HMAC secret (see
[ApiKey HMAC secret handling](api-key-hmac-secret-handling.md)).
