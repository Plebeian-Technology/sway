---
lat:
  mode: explanation
---

# Local error reporting design notes

Notes from wiring Sway's dev/test error collector (`rustrak-server`), found while auditing the whole path for a security review.

## Why SwayGzipOnlyTransport always compresses

`sentry-ruby` writes the `Content-Encoding` header on every request and leaves it EMPTY below its 30KB gzip threshold (`http_transport.rb: encoding = ""`).

Rustrak accepts an absent header as uncompressed, but reads an empty one as an encoding it does not know and answers 400. So every ordinary Ruby error was refused and the Ruby half reported nothing. `SwayGzipOnlyTransport` (`lib/sway_gzip_only_transport.rb`) forces `should_compress?` to always return true, so the header is never blank.

## Why SwayLocalErrorDsn refuses rather than warns

A wrong DSN is the one way dev/test errors quietly leave the machine, with nothing looking different. `SwayLocalErrorDsn.local?` (`lib/sway_local_error_dsn.rb`) refuses rather than warns for that reason.

`.browser_origin` returns nil unless the address is on this machine — a host policy must never be widened by a value somebody pasted into their environment, so the same refusal that stops the report being sent also stops the policy naming it. The port is only written when it is not the scheme's own, because a browser compares origins after dropping a default port.

`app/frontend/sway_utils/local_error_dsn.ts` asks the same question (`isLocalErrorCollectorDsn`) on the browser side. A wrong DSN is the one way dev/test errors quietly leave the machine, with nothing looking different, so it also refuses rather than warns, and it must agree with `SwayLocalErrorDsn` on the Ruby side. Unparseable is false: a DSN that cannot be read cannot be shown to be local.

`mobile/src/observability/local_error_dsn.ts` asks the same question for the mobile app, and its own test file states the same rationale: a wrong address is the one way dev errors quietly leave the machine. It adds one thing the other two platforms do not need — `dsnForThisPlatform` rewrites `localhost`/`127.0.0.1` to `10.0.2.2` on Android, since that is how the Android emulator reaches its host machine. The rewrite only touches a host that is already loopback; otherwise it would invent a local address from a remote one and walk straight past the guard above.

## Why send_default_pii and include_local_variables are set explicitly

`SwayLocalErrorReporting.apply` sets `config.send_default_pii = false` and `config.include_local_variables = false` explicitly.

`SwayLocalErrorReporting.apply` sets `config.send_default_pii = false` and `config.include_local_variables = false` explicitly, even though both are already the gem's defaults, because the security review asked for a measurement of each setting, not an assumption that the default held.

`include_local_variables` decides whether local variables travel inside a frame's stack trace — testimony text is a local on the model-prompt path, so leaving this on would let raw testimony leave the app in an error report. `send_default_pii` is what gates request bodies, headers, and cookies in sentry-ruby 6; there is no separate `max_request_body_size` setter in this version to fall back on.

## Why config.environment is set explicitly

`SwayLocalErrorReporting.apply` (`lib/sway_local_error_reporting.rb`) sets `config.environment = Rails.env.to_s` explicitly.

Sentry writes `"production"` when nothing sets this, so a collector built for development labelled every error production. Found while reading a stored event by hand.

## Why local_error_dsn.ts does not use new URL to parse the DSN (mobile)

`mobile/src/observability/local_error_dsn.ts` parses the DSN with a three-group regex (`/^(https?:\/\/[^@/]+@)([^:/]+)(.*)$/`) instead of `new URL`.

`mobile/src/observability/local_error_dsn.ts` parses the DSN with a three-group regex (`/^(https?:\/\/[^@/]+@)([^:/]+)(.*)$/`) instead of `new URL`: React Native ships a partial URL implementation, so reading `.hostname` from it is not dependable across versions. The three groups are the point — rebuilding the DSN from them is the only way to change the host without touching a key that happens to contain the same text. A first attempt used `match.replace(host, ...)` and rewrote the key instead.

## Why one spec sends a real request instead of reading a report back in memory

`spec/lib/error_report_on_the_wire_spec.rb` is the gate that was missing.

Every other check for the local error collector builds a report and reads it back in memory. That spec instead lets the real transport make a real request, catches it at the HTTP layer, and hands the bytes to something that refuses them the way the collector does — the same `Content-Encoding` check described above.

It exists because the whole Ruby half of error reporting was DEAD while the suite was green: the fault was one header (see `SwayGzipOnlyTransport` above), so only something reading headers, not report contents, could see it. Nothing leaves the machine — WebMock answers the request — so it runs anywhere.

## Why CSP and Sentry initializers require SwayLocalErrorDsn directly

[[config/initializers/content_security_policy.rb]] and [[config/initializers/sentry.rb]] load [[lib/sway_local_error_dsn.rb]] with an explicit `require` because Rails initializers run before Zeitwerk autoloading is ready in development and test.

## Why initLocalErrorCollector drops the BrowserSession integration

`initLocalErrorCollector` in [[app/frontend/sway_utils/sentry.ts]] filters `BrowserSession` out of Sentry's default integrations.

Rustrak does not implement Sentry session ingestion and discards session envelopes. Filtering `BrowserSession` out prevents the browser from sending session requests that the local collector ignores.
