---
lat:
  require-code-mention: true
---
# Malformed passkey credential tests

These tests send real fake-authenticator payloads, corrupted, through real WebAuthn verification, with no stubbed verify calls. The rule they pin is [[malformed-passkey-credentials#An unreadable credential is an invalid credential]].

## Web enrollment

The first-passkey callback answers each corrupted attestation with the verification-failed redirect, clears the registration session, and creates no user or passkey.

## Web phone sign-in

The phone-first sign-in callback answers each corrupted assertion with the verification-failed redirect, signs nobody in, and clears the authentication session.

## Web discoverable sign-in

The discoverable sign-in callback answers each corrupted assertion with the verification-failed redirect, signs nobody in, and clears the discoverable challenge.

## Web passkey addition

The add-a-passkey callback answers each corrupted attestation with success false and the verification-failed message, saves no passkey, and clears the add-passkey challenge.

## Mobile enrollment

The mobile registration callback answers each corrupted attestation with 401 invalid_credentials, deletes the cached challenge, leaves the SMS token unspent, and creates no user, passkey or bearer token.

## Mobile sign-in

The mobile sign-in callback answers each corrupted assertion with 401 invalid_credentials, deletes the cached challenge, and issues no bearer token.

## Mobile passkey addition

The mobile add-a-passkey callback answers each corrupted attestation with 401 invalid_credentials, deletes the cached challenge, leaves the SMS token unspent, and saves no passkey.

## Lookup errors pass through

An exception raised by the stored-passkey lookup block reaches the caller unchanged, so a defect in application code is not reported as an unreadable credential.

## Decode errors after the lookup are translated

A truncated authenticator data field, which fails to decode only after the lookup returned, becomes the malformed-credential error and keeps the original IOError as its cause.
