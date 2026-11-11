---
mode: explanation
summary: "Why the mobile sign-in challenge now names the flow outright as the web one always has, what the decoy it replaced was defending, and why that defence was both broken and already given away."
status: agent-extracted
related: [docs/explanation/discoverable-passkey-design.md, docs/explanation/passkey-only-sms-bootstrap.md]
---

<!-- vale Vale.Spelling = NO -->

# Account-existence disclosure on the sign-in challenge

`Users::Webauthn::SessionsController`'s sign-in challenge must never reveal
whether a phone number has a Sway account through its status code or
response shape. `Api::V1::SessionsController#challenge` used to hold itself
to a stricter bar than that, and no longer does.

## What the mobile challenge answers now, and what it stopped defending

`Api::V1::SessionsController#challenge` answers `{flow: "passkey"}` with a
`challenge_id` and nested `options` when the phone has a passkey, and
`{flow: "sms"}` when it does not — the same discriminated envelope the web
endpoint has always used, and the same information disclosure.

It used to answer every phone identically: a real challenge for
an account with a passkey, a challenge built around a deterministic decoy
credential id for anything else, so the response revealed nothing at all.
The client was expected to attempt the ceremony, fail on the device, and
fall back to SMS.

Two things were wrong with that, and they compound.

The fallback did not exist. The client checked for error names
`react-native-passkey` has never emitted, so the no-credential outcome the
decoy design depends on had never once been produced.
The mechanism had been decorative for its whole life.

And the failure it produced was not quiet. On iOS a ceremony with no
matching credential is a blocking system sheet reading "you don't have any
passwords or passkeys saved for this app", shown to someone signing up who
has never heard of a passkey, whose only correct move is to dismiss it. A
flow whose happy path for new users requires correctly dismissing a dialog
about a thing they do not have is not a fallback. Most people will take one
of the other buttons.

The property being defended was already published. The web endpoint answers
`{flow: "passkey"}` or `{flow: "sms"}` outright and always has, and that is
recorded below as an accepted leftover risk under its own rate limit. An
attacker enumerating phone numbers uses the web surface; the mobile decoy
cost every new user a confusing dialog and closed nothing an attacker could
not reach elsewhere.

What survives is the rate limiting: ten probes per IP and five per phone
per five minutes, unchanged. `#callback` still refuses a cached phone whose
user holds no passkey, which now guards a passkey deleted between the two
calls rather than a decoy.

## Why `#discoverable_challenge` exists as a separate, phone-free flow

`#discoverable_challenge` lets a caller sign in without naming anyone
first: an empty `allowCredentials` list and no phone number let the device
offer whichever Sway passkey it already holds, and `#callback` works out
who owns it from the credential id that comes back. The cached phone is
`nil` for this flow specifically so `#callback` can tell the two flows
apart. Because nothing is looked up by phone here, this path reveals
nothing about which accounts exist — there is no phone to probe against in
the first place. Passkeys that are not stored on-device (not
discoverable) still go through the phone-first `#challenge` flow.

## How the web sign-in flow (`Users::Webauthn::SessionsController`) achieves the same non-disclosure

The web `#create` action uses a different mechanism than the mobile
decoy-credential-id approach, aimed at the same goal: both branches (an
existing passkey user vs. a phone with none) answer 200 with a shared
`{flow:, ...}` envelope, so the status code alone can't tell an attacker
whether a phone has a passkey. The body still differs by the `flow` value
(`"passkey"` vs `"sms"`) — unavoidable, since the client needs to know
which ceremony to run — an accepted leftover risk, rate-limited to 5
probes per phone per 5 minutes. Uniform responses must never ADD an SMS
send beyond what the phone-first flow always sent.

`Users::Webauthn::SessionsController#discoverable_challenge` mirrors
`Api::V1::SessionsController#discoverable_challenge`: an EMPTY
`allow_credentials` list and no phone let the authenticator offer whatever
discoverable Sway credential it holds. Because nothing is looked up, the
response reveals nothing about which accounts exist, closing the leftover
risk the phone-first `{flow:}` envelope carries. Older non-resident
passkeys are not discoverable, so their owners keep using the phone-first
`#create` path unchanged.

## How the mobile client reads the envelope

`mobile/src/auth/passkeyAuth.ts` only CALLS the server's auth endpoints; it
defines no Rails routes itself. Every path comes from `Routes.*`
(`mobile/src/api/routes.ts`).

`passkeyAuth.signIn` throws `NoCredentialError` on the `flow: "sms"` branch
without running a ceremony at all, so a phone with no passkey never reaches
`Passkey.get` and never sees a system sheet. `AuthScreen` already treats
`NoCredentialError` as "ask for a code", so the branch needed no screen
changes.

`/sessions/challenge` answering 404 `{ code: "no_passkey_enrolled" }` also
becomes `NoCredentialError` — only older servers still send this; it is kept
so they keep working. `Passkey.isSupported() === false` and a ceremony
reporting `NotSupported` both become `PasskeyUnsupportedError`. Any other API
or network error passes through unchanged. `AuthScreen` decides what to show
next from which of these two error classes it catches.

On success, `passkeyAuth` saves to BOTH `tokenStore` (just the bearer
token) AND `sessionStore` (the whole record:
`{ bearer_token, device_id, user_id, expires_at }`). `sessionStore`'s
`device_id` is what `useSession.signOut` sends to `DELETE
/api/v1/devices/:id`, so the long-lived row for this install reliably
gets revoked.

### Why `mapPasskeyError` logs the raw native error in development

In development, `mapPasskeyError` logs the raw iOS/Android error so it can
be seen what really went wrong instead of only "Sign in failed". The
native library throws an `RNPasskeyError` whose type is one of
`cancelled`, `requestFailed`, `badConfiguration`, `timedOut`,
`notSupported`, or `unknown`; without this log the catch further up folds
that type into a generic message.

## Why `#callback` resolves the credential-driven path this way

`user_from_credential` works out who is signing in from the credential id
the device returned — `external_id` is unique across every passkey.
`relying_party.verify_authentication` then checks that credential against
the resolved user's own passkeys, so a made-up or guessed credential id
that happens to point at the wrong user still fails verification.
