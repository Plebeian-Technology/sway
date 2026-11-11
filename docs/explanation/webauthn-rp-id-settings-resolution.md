---
mode: explanation
summary: "Why config/initializers/webauthn.rb reads Sway::Settings.webauthn.rp_id instead of ENV directly, and why Sway::Settings (unlike EnvSecret) can be named this early in boot."
status: agent-extracted
related: [docs/reference/settings-value-resolution.md]
---

<!-- vale Vale.Spelling = NO -->

# Why `config/initializers/webauthn.rb` reads `Sway::Settings.webauthn.rp_id`

`config/initializers/webauthn.rb` sets `config.rp_id` from
`Sway::Settings.webauthn.rp_id`, falling back to `"app.sway.vote"` in
production and `nil` otherwise. `RelyingParty#relying_party` reads the same
declared setting. Both readers used to read `ENV["WEBAUTHN_RP_ID"]`
independently, which meant a value with a stray trailing newline
(`"app.sway.vote\n"`) could be trimmed by one reader and not the other, and
the two could disagree about whether it was a usable Relying Party id (the
"site" a passkey belongs to). Routing both through one declared setting
trims it once, in one place, so they can no longer disagree.

## Why this can name `Sway::Settings` but not `EnvSecret`

Files under `config/initializers/` still run before Zeitwerk (Rails'
autoloader) has loaded application classes, so `EnvSecret` — the credential
helper every other credential in Sway goes through — genuinely cannot be
named here. That part hasn't changed.

`Sway::Settings` is different: `config/application.rb` requires it by hand,
in its own class body, long before any file under `config/initializers/`
runs. That makes `Sway::Settings.webauthn.rp_id` available at this
point in boot even though `EnvSecret` is not.

## Why `RelyingParty#relying_party` logs the resolved values on every call

Debugging passkeys is painful: the iOS and Android clients only say "An
unknown error occurred" when the relying party id does not match the
domain the app is registered for. `#relying_party` logs the values the
client is about to receive, so a mismatch is obvious in the server log:

- `rp_id_source`: whether the id came from an environment variable, the
  production default, or was left nil for the gem to work out from the
  first allowed origin.
- `request_host`: the Host header the proxies actually delivered. If it is
  not the expected tunnel host, the phone skipped the tunnel.

## Why the mobile passkey callbacks log the origin the client reported

`#relying_party` logs the origins the server is willing to *accept*. Nothing
logged the origin a client actually *sent*, so the two halves of an origin
mismatch were never visible together — only the failure was.

That gap became concrete during phase 68. The
production allowlist in `RelyingParty#origins` gained two native-app entries,
`android:vote.sway.app` and `ios:<TEAMID>.vote.sway.app`, that no observed
ceremony had ever sent. Deciding whether to keep or revert them needed the
received value, and there was no way to obtain it short of attaching a
debugger to a physical device.

`#log_passkey_client_origin` closes that: the three `/api/v1` passkey
callbacks decode `clientDataJSON` and log its `origin`, `type` and, on
Android, `androidPackageName`. It is deliberately permanent rather than a
temporary probe, because the same line answers the recurring question behind
an `ASAuthorizationError` 1004 — the client says only "no credentials were
returned", while the server can now say which origin it was handed and which
ones it would have accepted.

## What a real iOS ceremony turned out to send

The capture came from a passkey creation ceremony run on a
physical iPhone against `rp_id` `<dev-tunnel-host>`:

```
webauthn.client_data origin="https://<dev-tunnel-host>" type="webauthn.create" android_package_name=nil request_host=<dev-tunnel-host>
```

An iOS client authenticating through Associated Domains reports its origin as
`https://<rp_id>` — the same shape a browser sends, and nothing like
`ios:<team-id>.<bundle-id>`. The two native-app entries were therefore strings
no client produces. They could never have matched a real ceremony, and they
widened the accepted set for nothing, so both were removed and the
production fallback is the three web origins again. The observed value is
covered by them once `rp_id` is `app.sway.vote`.

Android is not an argument for keeping `android:vote.sway.app`. A verified
Android client also sends `https://<rp_id>`; an unverified one sends
`android:apk-key-hash:<sha256>`. Neither is the removed string, and Android is
separately blocked by an empty `ANDROID_CERT_SHA256_FINGERPRINTS`,
which is why no Android half of the capture exists yet.

The pinned assertion lives in `spec/requests/api/v1/passkey_client_origin_spec.rb`
so the claim rests on a value that was observed rather than on reasoning about
what the platform ought to do.

The challenge nonce in `clientDataJSON` is not logged. A malformed or
undecodable value is warned about and swallowed, because a diagnostic must
never be able to fail a ceremony that would otherwise have succeeded.

## Why `rp_id_source` re-derives the source instead of re-reading the raw setting

`#rp_id_source` uses the exact same check `#relying_party` already used to
resolve `resolved_id`, rather than reading `Sway::Settings.webauthn.rp_id`
a second, independent time. A second read would report `"env"` even for a
value that is nothing but whitespace — which `#relying_party` had already
thrown away as blank — so the log line written to explain a mismatch would
blame the wrong source.

## Why the relying party `name` has no preview/staging suffix

`WebAuthn::RelyingParty#name` is built as `"sway-#{Rails.env}"`, straight
from the environment Rails is already running in. There is no second
source of truth for that, and nothing sets a preview switch anywhere in
this repository, so no additional suffix is added.

`IS_PREVIEW` itself is not dead: `.dockerdev/compose.yml`'s `preview`
service still sets `IS_PREVIEW=1` alongside `RAILS_ENV=production` for its
own local `bin/rails server`. It is absent from `config/deploy.yml` and
`.kamal/secrets-common`, so nothing deployed loses this suffix — only that
one local compose container's displayed relying-party name changes from
`"sway-production-preview"` to `"sway-production"`. Name only; it takes no
part in validating a ceremony.

## Why `spec/controllers/concerns/relying_party_spec.rb` is a new file, not a migration

It follows the pattern in `spec/controllers/concerns/mobile_format_negotiation_spec.rb`:
a throwaway controller mounts `RelyingParty` and `#relying_party` is called
directly. Nothing varied either `WEBAUTHN_RP_ID` or
`WEBAUTHN_ALLOWED_ORIGINS` before the settings consolidation —
both readers read raw `ENV` — so there was no existing spec exercising this
behavior to migrate, making this the only group with nothing
to migrate.
