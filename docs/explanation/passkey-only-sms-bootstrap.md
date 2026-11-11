---
mode: explanation
summary: "Why SMS-verified enrollment is the bootstrap path for a phone with no passkey yet, but is blocked once a passkey exists for that phone -- SMS is not a passkey-recovery channel."
status: agent-extracted
related: [docs/explanation/discoverable-passkey-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Passkey-only auth and the SMS bootstrap path

Sway is passkey-only for sign-in. SMS-verified passkey enrollment
(`Api::V1::RegistrationsController#create` and `#callback`) is the
bootstrap path for a phone that has no passkey yet — including phones that
already have a `User` row but no passkey (a seeded admin, or a web account
that never finished passkey setup).

Both `#create` and `#callback` block enrollment only when a passkey already
exists for the phone in question; in that case the caller must sign in
with their existing passkey or contact support. SMS is deliberately not a
recovery channel for a lost passkey — allowing it would let anyone who can
receive a text to the phone number displace an existing passkey.

`#callback` re-checks this inside the transaction that creates the user
records, closing a TOCTOU race where a passkey was enrolled by another
request between `#create` and `#callback`. A bare `User` row with no
passkey is fine to attach the new credential to.

## Why sign-in accepts only a passkey

`Api::V1::SessionsController` and `Users::Webauthn::SessionsController`
both accept only a passkey for sign-in. SMS alone is deliberately
insufficient for signing in — it only proves phone ownership while
enrolling a first passkey, through `/phone_verification` and
`/registrations`.

## `Api::V1::RegistrationsController`: the two-step enrollment shape and token handling

Passkey enrollment happens in two steps, mirroring
`Users::Webauthn::RegistrationController`:

- `POST /api/v1/registrations` accepts `sms_verified_token` + `phone` and
  returns WebAuthn create options plus a `challenge_id` tied to a cache
  entry.
- `POST /api/v1/registrations/callback` verifies the credential, creates
  `Passkey` + `UserDevice` + `ApiKey`, and seeds 4 `NotificationPreference`
  rows.

`#create` PEEKS at the `sms_verified_token` — checks it without spending it
— and stores it in the cache next to the WebAuthn challenge. On `#callback`
success, both the `challenge_id` and the `sms_verified_token` are deleted
INSIDE the `User.transaction` that creates the user records, so each token
can be used exactly once: a `#create` that never completes `#callback`
doesn't burn the SMS token, and a successful `#callback` can't be replayed
with the same challenge or token.

Registration is passkey-only: the user's address is collected only after
they are signed in, via `POST /sway_registration` — the same order the web
flow uses.

## `mobile/src/auth/smsAuth.ts`: proving you hold a phone number, before your first passkey

Sway's auth model on mobile: SMS is NOT a way to sign in. Passkeys are the
only sign-in method. SMS exists only to confirm that a real person holds
the phone number being registered, which unlocks the very first passkey
enrollment for that number. There is no SMS sign-in and no SMS recovery —
a lost passkey means contacting Sway support.

Two steps:

1. `requestCode(phone)` → `POST /api/v1/phone_verification` (204)
2. `verifyCode(phone, code)` → `POST /api/v1/phone_verification/verify`
   (200 → `sms_verified_token`), then →
   `passkeyAuth.register(phone, token)` (spends the token while enrolling
   the very first passkey for a brand-new account)

There used to be a `smsFallbackLogin()` that posted to `/api/v1/sessions`
and signed a user in on the SMS token alone, with no passkey step. It was
removed because it went around the passkey-only rule.

The server accepts an `sms_verified_token` once, and only within 10
minutes; sending it again returns 401 `invalid_sms_token`.
