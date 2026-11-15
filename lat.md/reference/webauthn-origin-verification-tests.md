---
lat:
  require-code-mention: true
---
# WebAuthn origin verification tests

These tests run real WebAuthn verification, with no stubbed verify calls, against credentials made for the wrong origin, the wrong relying party or a stale sign count, and against Android app origins.

## Web enrollment from another origin

The first-passkey callback refuses a credential whose client data names another origin with the verification-failed redirect, clears the registration session, and creates no user or passkey.

## Web enrollment for another relying party

The first-passkey callback refuses a credential made for another relying party id with the verification-failed redirect, clears the registration session, and creates no user or passkey.

## Web phone sign-in with a stale sign count

The phone-first sign-in callback refuses an assertion whose sign count is not above the stored one with the fixed passkey-verification redirect, signs nobody in, and leaves the stored sign count unchanged.

## Mobile enrollment from a configured Android app

The mobile registration callback accepts a credential whose origin is the apk-key-hash of a configured certificate fingerprint, and answers with a bearer token and a saved passkey.

## Mobile enrollment from an unknown Android app

The mobile registration callback refuses a credential whose apk-key-hash matches no configured fingerprint with 401 invalid_credentials, creates no user, and leaves the SMS token unspent.
