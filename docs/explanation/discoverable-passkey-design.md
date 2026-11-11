---
mode: explanation
summary: "Why Sway registers passkeys with resident_key: preferred (discoverable credentials), how a failed discoverable sign-in is classified so only the failures nobody caused are reported and shown, and the SMS-gated add-a-passkey flow that lets an already-enrolled user add a second device."
status: agent-extracted
related: [docs/explanation/passkey-management-page-overview.md, docs/explanation/passkey-aaguid-registry.md]
---

<!-- vale Vale.Spelling = NO -->

# Discoverable passkeys and the SMS-gated add flow

## Why registration asks for `resident_key: "preferred"`

Every passkey-registration ceremony in Sway — first-time enrollment
(`Api::V1::RegistrationsController`, `Users::Webauthn::RegistrationController`)
and adding an additional passkey to an existing account
(`Api::V1::PasskeysController`, `Users::PasskeysController`) — asks for a
discoverable (resident) credential with `authenticator_selection:
{resident_key: "preferred", ...}`.

"Discoverable" means the browser or OS can offer this passkey at sign-in
without the user typing who they are first — the device holds enough
information about the credential to present it on its own. `"preferred"`
never hard-fails enrollment: an authenticator without resident storage
falls back to the ordinary phone-first sign-in path, so existing users and
older hardware are unaffected.

## Why an already-signed-in user still needs a fresh SMS token to add a passkey

`Api::V1::PasskeysController` and `Users::PasskeysController` both let an
already-enrolled user add an additional passkey to their account — the
mobile and web twins of the same flow. Bearer/cookie auth alone is not
enough to gate this: the required trust level is a fresh SMS token tied to
the caller's own phone, obtained through the phone-verification endpoints
immediately beforehand. Without that extra step, a stolen bearer token or
hijacked session could quietly enroll an attacker's device onto the
account. This is distinct from first-time registration
(`Api::V1::RegistrationsController`, which 409s once a phone already has a
passkey): here the caller already has one and is adding another to the
SAME account.

## Why the cached challenge is bound to the authenticated caller

The add-a-passkey callback binds the cached WebAuthn challenge to the
`user_id` of the caller who requested it, so one user's `challenge_id` can
never be used to enroll a credential onto another account.

## `useWebAuthnAuthentication.startDiscoverableAuthentication`'s return contract

`startDiscoverableAuthentication`
(`app/frontend/hooks/authentication/useWebAuthnAuthentication.ts`) runs the
discoverable WebAuthn flow (with an empty `allowCredentials` list) so the
device can surface the user's own synced passkey on its own — or, on a new
device, offer the "use a passkey from a nearby device" QR code flow. It
returns the signed assertion on success, or `undefined` when the user
cancels or has no usable passkey (a `NotAllowedError`), in which case the
caller falls back to the phone-number-first form. Older, non-resident
passkeys aren't discoverable this way, so their owners just fall through
to the phone-first flow automatically. A `NotAllowedError` (cancel / no
credential / timeout) is the normal "fall back to phone" signal, not an
error to surface — but only when a person could have caused it. The hook
also returns a `discoverableFailure` reason, which is `null` for those and
a short slug for the rest; the next section is why.

## Why a failure the reader could not have caused is both reported and shown

Staying quiet is right for the two failures the flow was built around — the
reader cancelled, or this device holds no passkey. It was wrong for a third
kind nobody had allowed for. Firefox on iOS reached the site over plain
`http`, where `navigator.credentials` does not exist, so the call could
never start. The reader saw the screen dim and come back with
nothing said, and nothing reached Sentry either, so the fault survived until
somebody reported it by hand.

The browser will not say which kind it was. All three arrive as
`NotAllowedError`, deliberately, so that a site cannot learn which passkeys
a reader holds. `classifyPasskeyFailure` in
`app/frontend/sway_utils/passkey_failure.ts` therefore decides from what it
can observe instead of from the error:

- An insecure context, or a browser with no `PublicKeyCredential` at all, is
  the environment's fault whatever the error says. Reported.
- A `NotAllowedError` that came back faster than a person could have seen and
  dismissed a native sheet was refused by the browser, not by anyone.
  Reported. `HUMAN_DISMISS_FLOOR_MS` is the cut, and it is a heuristic — the
  cost of setting it too high is a silent fault, the cost of setting it too
  low is noise in Sentry.
- A slower `NotAllowedError`, and any `AbortError`, is a person. Silent, as
  before.
- Any other `DOMException` names a configuration fault, such as an `rp_id`
  the origin may not claim. Reported.

Reports go through `reportOnce`, so a browser that fails on every tap files
one issue per reason per day rather than one per tap.

## What the reader sees, and why it names no cause

The same line that decides what reaches Sentry decides what reaches the
person in front of the screen, because it is the same question: could anyone
have caused this? `useWebAuthnAuthentication` keeps the classifier's answer
as `discoverableFailure` — `null` when the failure reads as a person, a
reason slug otherwise — and clears it at the start of every fresh attempt. A
challenge request that fails before the ceremony can even begin is
`challenge-request-failed`, on the same footing: nobody could have cancelled
a sheet that never opened.

`PasskeyPanel` reads that value and, when it is set, draws a warning above
the phone form and moves focus into the phone field. So the fallback is
visible rather than assumed, and the field it points at is the one already
waiting for input. A cancel still falls through in silence, exactly as
before — a person who dismissed a sheet on purpose does not need to be told
they dismissed it.

The notice says only that a passkey sign-in did not work and that the phone
number below is the way on. It names no cause, because the browser will not
say what the cause was and a guess would be worse than nothing, and it shows
no error name or message, because neither means anything to a reader. The
reason slug stays behind the scenes, in the Sentry report.

## Why `discoverable_callback` looks up the user from the credential, not a phone

`Users::Webauthn::SessionsController#discoverable_callback` verifies the
signed WebAuthn response and finds the user FROM the returned credential
— never from a phone number. The stored passkey's owner is the account;
a discoverable (resident) credential carries enough information for the
authenticator to present itself without the caller supplying any
identifier first, so there is no phone lookup step in this flow.

## `mobile/src/auth/passkeyAuth.ts`: the mobile twin

A passkey is a key kept on the device that stands in for a password,
unlocked with Face ID, a fingerprint, or a PIN. `passkeyAuth.signInDiscoverable`
is the mobile client's half of the discoverable flow above: it signs in
without saying who you are — no phone number goes to the server, since the
passkey the device hands back is enough for the server to work out which
account it belongs to.

`passkeyAuth.addPasskey` adds another passkey to an account that is
already signed in — the mobile twin of the SMS-gated add flow
above.

`signInDiscoverable` asks for a challenge with an empty `allowCredentials`
list and sends no phone number, so the phone offers whichever passkey it
already holds — one synced to the account, or the "use a passkey from a
nearby device" flow on a brand-new phone — and the server works out the
account from what comes back. It throws `NoCredentialError` when the user
cancels or has no such passkey, which sends `AuthScreen` back to asking
for a phone number.

`addPasskey` requires the caller to hold a fresh `sms_verified_token` tied
to that account's phone (from `smsAuth.requestCode`/`verifyCode`);
checking by SMS again keeps this a two-factor step. The session is left
alone, so the user stays signed in. It returns the new passkey's id and
label for the list.
