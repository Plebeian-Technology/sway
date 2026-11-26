---
lat:
  mode: explanation
---

# Discoverable passkey design

Discoverable passkeys enable returning readers to authenticate securely without typing a phone number prior to credential presentation.

The authentication subsystem coordinates resident WebAuthn credentials, environmental failure classification, and fallback mechanisms for devices without resident key support.

## What the reader sees during passkey fallback and why it names no cause

When discoverable passkey authentication encounters an unrecoverable condition, Sway guides the reader to phone verification without speculating on failure causes.

Browsers issue generic `NotAllowedError` exceptions for diverse scenarios including insecure contexts, hardware absences, and timeouts. Speculating on internal causes risks misleading readers. [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] supplies `auth.passkeyPanel.passkeyFallback` to direct users cleanly to phone verification while diagnostic classifications remain in telemetry.

## Why registration asks for resident_key: "preferred"

Passkey registration ceremonies request discoverable credentials using `resident_key: "preferred"` to support seamless return visits without blocking older authenticators.

Every registration ceremony — initial enrollment in `Api::V1::RegistrationsController` and `Users::Webauthn::RegistrationController`, plus secondary passkey enrollment in `Api::V1::PasskeysController` and `Users::PasskeysController` — requests resident credentials.

Discoverable credentials permit browsers or authenticators to present user credentials automatically during sign-in without requiring prior phone number entry. The `"preferred"` configuration prevents registration failures on authenticators lacking resident key storage, seamlessly falling back to standard phone-first authentication.

## Why an already-signed-in user still needs a fresh SMS token to add a passkey

Adding a new passkey to an existing account requires a freshly verified SMS token to guard against session hijacking.

`Api::V1::PasskeysController` and `Users::PasskeysController` permit enrolled users to register additional devices. Session cookies and bearer tokens alone provide insufficient security for this credential modification. Requiring a fresh SMS token tied to the user's phone ensures an attacker holding a stolen session token cannot register an unauthorized authenticator onto the account.

On the web, a passed SMS check opens a ten-minute window ([[app/controllers/users/passkeys_controller.rb#PasskeysController#ADD_PASSKEY_VERIFY_WINDOW]]) for adding or removing one passkey. The window lives in the browser session, but the reader each request acts for comes from a bearer token whenever one is sent, so a session and a token can name two different accounts. The window therefore records the account that passed the check, and it counts only for a request whose reader is that same account. Without that, a person who passed the check on their own account could send their session cookie with another account's bearer token and add or remove that account's passkeys with no text sent to its phone.

## Why the cached challenge is bound to the authenticated caller

WebAuthn registration challenges bind to the user identifier of the requesting caller in the challenge cache.

Binding the cached challenge to the requesting user's `user_id` ensures a `challenge_id` issued to one account cannot be exploited to register a credential onto a different account.

## useWebAuthnAuthentication.startDiscoverableAuthentication return contract

`startDiscoverableAuthentication` executes discoverable authentication with empty allowed credentials to trigger resident credential selection or hybrid QR flows.

The hook returns a signed assertion on success or `undefined` when an operation is cancelled or lacks resident credentials. A standard `NotAllowedError` signals a graceful fallback to phone entry rather than an error condition requiring user alerts. The hook also returns `discoverableFailure`, providing diagnostic slugs for non-user causes.

## Why a failure the reader could not have caused is both reported and shown

Failures resulting from environment limitations or configuration defects are reported to telemetry and presented to users, distinguishing them from intentional user dismissals.

When browsers refuse credential requests due to insecure contexts or missing APIs, `classifyPasskeyFailure` evaluates observable conditions rather than relying solely on generic error types:

- Insecure contexts or missing `PublicKeyCredential` support indicate environment incompatibilities and are reported.
- Rapid `NotAllowedError` exceptions returning faster than `HUMAN_DISMISS_FLOOR_MS` indicate browser-level rejections rather than user dismissal and are reported.
- Slower `NotAllowedError` exceptions or `AbortError` instances represent user actions and remain silent.
- Other `DOMException` occurrences represent configuration errors such as origin mismatches and are reported.

Telemetry reports utilize `reportOnce` throttling to limit issue generation to one event per failure type daily.

## Why discoverable_callback looks up the user from the credential, not a phone

`Users::Webauthn::SessionsController#discoverable_callback` verifies signed assertions and resolves user accounts directly from credential identifiers.

Discoverable authentication supplies sufficient credential metadata for authenticators to identify the account directly, eliminating the need for upfront phone lookups during discoverable session verification.

## Mobile passkey authentication mechanics

`mobile/src/auth/passkeyAuth.ts` implements client-side discoverable sign-in and SMS-gated enrollment for mobile applications.

`signInDiscoverable` requests credentials with empty candidate lists, enabling devices to present resident credentials or hybrid nearby-device prompts. Operations throwing `NoCredentialError` gracefully return users to phone verification.

`addPasskey` requires callers to present a valid `sms_verified_token` while maintaining the existing user session, ensuring dual-factor verification for secondary authenticator additions.

## Why the phone input carries the webauthn autocomplete token

The phone input in [[app/frontend/components/auth/PasskeyPanel.tsx#PasskeyPanel]] declares `autoComplete="tel webauthn"` so browsers can offer saved passkeys or hybrid QR-code sign-in directly from the autofill prompt.

In Chrome and Safari, the `webauthn` token surfaces conditional mediation silently alongside phone autofill. In Brave over HTTPS, it triggers a one-time permission prompt, which is why the hint beneath the input warns the reader that the browser may ask to discover passkeys on their devices.
