---
mode: explanation
summary: "What an AAGUID is, where PasskeyAaguidRegistry's table comes from, and why some saved passkey rows can never resolve to a friendly name."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# PasskeyAaguidRegistry background

`PasskeyAaguidRegistry` (`lib/passkey_aaguid_registry.rb`) maps a
WebAuthn AAGUID to a friendly authenticator name.

## What an AAGUID is

An AAGUID is a 128-bit identifier baked into a passkey authenticator at
manufacture time. It identifies the *model* of authenticator (say, a YubiKey
5), not the individual credential. The table in `PasskeyAaguidRegistry::KNOWN`
is curated from the public `passkeydeveloper/passkey-authenticator-aaguids`
registry; when an authenticator is missing, `friendly_name` returns nil and
the caller shows "Unknown device".

## Why some saved passkeys can never resolve to a name

AAGUID is only sent while a passkey is being registered, never during
sign-in, so passkey rows saved before this lookup existed stay nil — there
is no way to backfill them short of re-registration.
