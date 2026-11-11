---
mode: explanation
summary: "Why mobile Sentry init is deliberately bare (no replay, 20% trace sampling, dev routed to the local collector instead of Sentry), and where the replay opt-out sits in the config shape."
status: agent-extracted
related: [docs/explanation/local-error-reporting-design.md, docs/explanation/sway-error-scrubber-design.md, docs/explanation/error-scrubber-empty-fingerprint-bug.md]
---

<!-- vale Vale.Spelling = NO -->

# Mobile Sentry init design

`mobile/src/observability/sentry.ts` sets up Sentry (the crash and error
reporting service) deliberately bare:

- No session replay, so a user's on-screen actions are never recorded.
- Only 20% of traces are sampled in production, to keep bandwidth and cost
  down.
- Development never reaches Sentry. It reports to a collector on the
  machine running the dev server instead, so local noise stays out of the
  production data and no error leaves that machine (see
  [Local error reporting design](local-error-reporting-design.md)). This
  reaches the iOS simulator and the Android emulator. A phone on the
  network cannot reach it, by choice: the collector listens on loopback
  only, so nothing off that machine can read the errors.

For how the push-token breadcrumb hook (`scrubPushTokenBreadcrumb`) keeps
native push tokens out of Sentry events, see
[SwayErrorScrubber design notes](sway-error-scrubber-design.md).

Uploading source maps from real release builds is the build pipeline's
job, via the Expo plugin, not this file's.

## Why `debug: true` only in the local-collector branch

The SDK says nothing when a send fails, and this collector's whole failure
mode is silence: the address was right, the emulator could reach the
collector, the error was thrown, and nothing arrived. `debug: true` is only
on in development, where the extra Metro output is the point.

`environment: "development"` is set explicitly for the same reason as the
Ruby side: Sentry writes `"production"` when nothing sets this, so every
stored development error was labelled production until someone read one.

## Why the replay opt-out sits at the root, not under `_experiments`

Session replay is turned off explicitly (`replaysSessionSampleRate: 0`,
`replaysOnErrorSampleRate: 0`) at the ROOT of the `Sentry.init` config, not
under `_experiments`. This SDK marks the `_experiments` copies of those
settings deprecated and says they go in the next major version, so writing
them there would mean a privacy setting that disappears on an upgrade with
nothing to show for it. The `MobileReplay` integration loads either way; a
rate of zero is what stops it recording.

The production branch (`initSentry`'s non-`__DEV__` path) carries the same
placement note, since it is the branch that reports to Sentry for real and
so is the one that matters most.
