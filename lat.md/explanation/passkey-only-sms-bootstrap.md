---
lat:
  mode: explanation
---

# Passkey-only auth and the SMS bootstrap path

Sway is passkey-only for sign-in.

SMS-verified passkey enrollment (`Api::V1::RegistrationsController#create` and `#callback`) is the bootstrap path for a phone that has no passkey yet — including phones that already have a `User` row but no passkey (a seeded admin, or a web account that never finished passkey setup).

Both `#create` and `#callback` block enrollment only when a passkey already exists for the phone in question; in that case the caller must sign in with their existing passkey or contact support. SMS is deliberately not a recovery channel for a lost passkey — allowing it would let anyone who can receive a text to the phone number displace an existing passkey.

`#callback` re-checks this inside the transaction that creates the user records, closing a TOCTOU race where a passkey was enrolled by another request between `#create` and `#callback`. A bare `User` row with no passkey is fine to attach the new credential to.

## Why sign-in accepts only a passkey

`Api::V1::SessionsController` and `Users::Webauthn::SessionsController` both accept only a passkey for sign-in.

SMS alone is deliberately insufficient for signing in — it only proves phone ownership while enrolling a first passkey, through `/phone_verification` and `/registrations`.

## Api::V1::RegistrationsController: the two-step enrollment shape and token handling

Passkey enrollment happens in two steps, mirroring `Users::Webauthn::RegistrationController`:

- `POST /api/v1/registrations` accepts `sms_verified_token` + `phone` and
  returns WebAuthn create options plus a `challenge_id` tied to a cache
  entry.
- `POST /api/v1/registrations/callback` verifies the credential, creates
  `Passkey` + `UserDevice` + `ApiKey`, and seeds 4 `NotificationPreference`
  rows.

`#create` PEEKS at the `sms_verified_token` — checks it without spending it — and stores it in the cache next to the WebAuthn challenge. In `#callback`, both the `challenge_id` and the `sms_verified_token` are deleted INSIDE the `User.transaction` that creates the user records, and the boolean return value of [[app/services/sms_verification_token.rb#SmsVerificationToken#consume!]] is enforced (in both [[app/controllers/api/v1/registrations_controller.rb#RegistrationsController#callback]] and [[app/controllers/api/v1/passkeys_controller.rb#PasskeysController#callback]]): when `consume!` returns `false`, the transaction rolls back and the controller returns 401 `invalid_sms_token`. The registrations `#callback` calls `consume!` as the last statement of that transaction, so the token is spent only when account creation has otherwise succeeded, and a failed write leaves it valid until it expires ([[sms-verification-token-design#Why the token is spent last]]). The non-destructive `peek` check runs first of all, ahead of the already-registered check, because the first callback of a replayed pair has already created the passkey — checked the other way round, a replay would answer 409 `phone_already_registered` and disclose that the account exists. When WebAuthn verification raises `WebAuthn::Error`, `#callback` deletes the cached challenge key while leaving the `sms_verified_token` unconsumed for a fresh ceremony.

Registration is passkey-only: the user's address is collected only after they are signed in, via `POST /sway_registration` — the same order the web flow uses.

## mobile/src/auth/smsAuth.ts: proving you hold a phone number, before your first passkey

Sway's auth model on mobile: SMS is NOT a way to sign in.

Passkeys are the only sign-in method. SMS exists only to confirm that a real person holds the phone number being registered, which unlocks the very first passkey enrollment for that number. There is no SMS sign-in and no SMS recovery — a lost passkey means contacting Sway support.

Two steps:

1. `requestCode(phone)` → `POST /api/v1/phone_verification` (204)
2. `verifyCode(phone, code)` → `POST /api/v1/phone_verification/verify`
   (200 → `sms_verified_token`), then →
   `passkeyAuth.register(phone, token)` (spends the token while enrolling
   the very first passkey for a brand-new account)

There used to be a `smsFallbackLogin()` that posted to `/api/v1/sessions` and signed a user in on the SMS token alone, with no passkey step. It was removed because it went around the passkey-only rule.

The server accepts an `sms_verified_token` once, and only within 10 minutes; sending it again returns 401 `invalid_sms_token`.

## Why the sign-in challenge is deleted inside the callback transaction

[[app/controllers/api/v1/sessions_controller.rb#SessionsController#callback]] deletes the cached WebAuthn challenge inside the same transaction that updates the passkey and issues the bearer token.

Spending the challenge inside the transaction guarantees that a challenge can be used once and only once. If token issuance rolls back, the challenge is not silently lost before a retry; once the transaction commits — or if verification raises `WebAuthn::Error` or [[app/controllers/users/webauthn/sessions_controller.rb#UnknownPasskeyError]] — the challenge key is removed from `Rails.cache` so replaying the same challenge returns an invalid-challenge refusal.
