---
mode: explanation
summary: "The pre-consolidation history of WEBAUTHN_RP_ID and WEBAUTHN_ALLOWED_ORIGINS, and why rp_id deliberately has no default in Sway::Settings::Webauthn."
status: agent-extracted
related: ["docs/reference/settings-value-resolution.md"]
---

<!-- vale Vale.Spelling = NO -->

# Webauthn settings: consolidation history and the rp_id fallback split

## Why allowed_origins and rp_id share one prefix

`Sway::Settings::Webauthn` declares `allowed_origins` (which origins may
complete a passkey ceremony) and `rp_id` (the domain a passkey is tied to)
under one `env_prefix "WEBAUTHN"`. This settings phase has only two groups
whose attributes all share a common name prefix this way — `rate_limits`
is the other — because in both cases the attributes describe facets of one
underlying concept rather than unrelated settings that happen to live in
the same file.

## Before Sway::Settings::Webauthn existed

`WEBAUTHN_RP_ID` used to be read three times: through `EnvSecret` in
`RelyingParty#relying_party`, again in `RelyingParty#rp_id_source`, and raw
in `config/initializers/webauthn.rb`. `WEBAUTHN_ALLOWED_ORIGINS` was read
twice, raw in both `RelyingParty#origins` and the initializer, and their
production fallbacks disagreed on length.

Both readers now read the one `Sway::Settings::Webauthn` declaration
instead.

## Why rp_id has no default

`rp_id` has no default, and is not `required` — `nil` is itself a
legitimate, honest value for this attribute, not an omission.

`RelyingParty#relying_party` and `config/initializers/webauthn.rb` each
supply their own fallback when this is unset. In
production both pin `app.sway.vote`
(`config/initializers/webauthn.rb`'s `config.rp_id` assignment). Outside production they
deliberately differ: the concern answers a real request and names the host
the phone actually reached, which is what lets a phone on the tunnel
address sign in, while the initializer has no request and leaves the value
`nil` for the library to derive from the first allowed origin (true only outside production).

Giving `rp_id` a default in `Sway::Settings::Webauthn` would collapse both
readers onto one fallback and break the tunnel case.

## Why the native apps need no origin entries of their own

Both production fallbacks list the three web origins and nothing else.

The reasoning that once put `android:vote.sway.app` and
`ios:<TEAMID>.vote.sway.app` alongside them was that a ceremony started
inside a native app must be recognised as the same Relying Party — the "site"
a passkey belongs to — as the website. That much is true. What is not true is
that a native app announces itself with a scheme-prefixed identifier. An iOS
app reaching the site through Associated Domains, and an Android app reaching
it through a verified Digital Asset Links file, both report
`window.location.origin` as `https://<rp_id>`, exactly as a browser does. The
association files are what make the app count as the site; the origin string
is unremarkable.

A real ceremony on a physical iPhone confirmed it, and
[webauthn-rp-id-settings-resolution.md](webauthn-rp-id-settings-resolution.md)
records the captured line. The two entries were removed: they
matched nothing, and an allowlist entry that can never match is a widened
accepted set bought for nothing.

An Android app whose asset-links file does not verify is the one case that
reports something else — `android:apk-key-hash:<sha256>` — and that value was
not the removed string either. Verification is the fix there, and is still
to be done.

## Why `.well-known/webauthn` is a route, not a static file

`.well-known/webauthn` (see
[the related-origin requests spec](https://web.dev/articles/webauthn-related-origin-requests#browser_support))
is drawn as a route rather than served as a static file so the controller
picks which hosts answer. It lists five (`WellKnownController::WEBAUTHN_HOSTS`)
and `sway.vote` is one of them — the comment that used to sit at the route
declaration said only `app.sway.vote` answered, which production disproves.

## How `spec/config/webauthn_initializer_spec.rb` tests a boot-time initializer

`config/initializers/webauthn.rb` runs once at boot, so its real effect is
whatever `WebAuthn.configuration` held before the first request — nothing
a later request can observe changing. Following
`spec/config/sentry_initializer_spec.rb`'s pattern, the spec re-runs the
initializer's own configuration block against a stubbed `Rails.env` and a
swapped `Sway::Settings.webauthn` instance (`with_app_config`), rather than
asserting on whatever the one real boot happened to produce — which would
only ever prove the test process's own boot-time settings, not the
initializer's behavior under a setting a real boot might see.
