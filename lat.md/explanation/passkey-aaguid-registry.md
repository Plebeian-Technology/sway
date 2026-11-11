---
lat:
  mode: explanation
---

# PasskeyAaguidRegistry background

`PasskeyAaguidRegistry` (`lib/passkey_aaguid_registry.rb`) maps a WebAuthn AAGUID to a friendly authenticator name.

## What an AAGUID is

An AAGUID is a 128-bit identifier baked into a passkey authenticator at manufacture time.

It identifies the *model* of authenticator (say, a YubiKey 5), not the individual credential. The table in `PasskeyAaguidRegistry::KNOWN` is curated from the public `passkeydeveloper/passkey-authenticator-aaguids` registry; when an authenticator is missing, `friendly_name` returns nil and the caller shows "Unknown device".

## Why some saved passkeys can never resolve to a name

AAGUID is only sent while a passkey is being registered, never during sign-in, so passkey rows saved before this lookup existed stay nil — there is no way to backfill them short of re-registration.

## Why the all-zeros AAGUID returns nil

`PasskeyAaguidRegistry.friendly_name` in [[lib/passkey_aaguid_registry.rb]] returns `nil` for `"00000000-0000-0000-0000-000000000000"` alongside `nil`, blank, and unmapped values.

WebAuthn authenticators send the all-zeros AAGUID placeholder when attestation is suppressed for privacy, so treating it as unknown lets callers fall back to a generic device label.
