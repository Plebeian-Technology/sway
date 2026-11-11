---
lat:
  mode: explanation
---

# Mobile Sentry init design

`mobile/src/observability/sentry.ts` sets up Sentry (the crash and error reporting service) deliberately bare:

- No session replay, so a user's on-screen actions are never recorded.
- Only 20% of traces are sampled in production, to keep bandwidth and cost
  down.
- Development never reaches Sentry. It reports to a collector on the
  machine running the dev server instead, so local noise stays out of the
  production data and no error leaves that machine (see
  [[docs/explanation/local-error-reporting-design.md|Local error reporting design]]). This
  reaches the iOS simulator and the Android emulator. A phone on the
  network cannot reach it, by choice: the collector listens on loopback
  only, so nothing off that machine can read the errors.

For how the push-token breadcrumb hook (`scrubPushTokenBreadcrumb`) keeps native push tokens out of Sentry events, see [[docs/explanation/sway-error-scrubber-design.md|SwayErrorScrubber design notes]].

Uploading source maps from real release builds is the build pipeline's job, via the Expo plugin, not this file's. The values that job and this file need reach the build as described in [[mobile-sentry-init-design#Why the store build requires the Sentry values]].

## Why debug: true only in the local-collector branch

The SDK says nothing when a send fails, and this collector's whole failure mode is silence: the address was right, the emulator could reach the collector, the error was thrown, and nothing arrived.

`debug: true` is only on in development, where the extra Metro output is the point.

`environment: "development"` is set explicitly for the same reason as the Ruby side: Sentry writes `"production"` when nothing sets this, so every stored development error was labelled production until someone read one.

## Why the replay opt-out sits at the root, not under _experiments

Session replay is turned off explicitly (`replaysSessionSampleRate: 0`, `replaysOnErrorSampleRate: 0`) at the ROOT of the `Sentry.init` config, not under `_experiments`.

This SDK marks the `_experiments` copies of those settings deprecated and says they go in the next major version, so writing them there would mean a privacy setting that disappears on an upgrade with nothing to show for it. The `MobileReplay` integration loads either way; a rate of zero is what stops it recording.

The production branch (`initSentry`'s non-`__DEV__` path) carries the same placement note, since it is the branch that reports to Sentry for real and so is the one that matters most.

## Why the Metro config comes from Sentry

`mobile/metro.config.js` builds its config with Sentry's `getSentryExpoConfig` rather than Expo's own `getDefaultConfig`, so every release bundle carries a Debug ID.

The Sentry helper calls Expo's default config and adds a serializer that stamps each bundle and its source map with a matching Debug ID. The build uploads the map under that ID and an event from the bundle names the same ID, which is how Sentry finds the map for a production stack trace. Without the stamp the match is not guaranteed, and a trace can stay minified even though the upload succeeded. NativeWind still wraps the result.

## Why the DSN is trimmed at config time

`mobile/app.config.ts` strips whitespace from `SENTRY_DSN_MOBILE` before it becomes `extra.sentryDsn`, and a blank value reads as absent.

A newline pasted into the vault item along with the DSN would otherwise ride into the binary unseen. The browser build lost its reporting that way — [[browser-error-reporting#A trailing newline in a DSN turns reporting off without saying so]]. Reading blank as absent makes `initSentry` return early exactly as it does when the variable is unset, so the two cases look alike.

## Why the store build requires the Sentry values

The store build scripts ask `with-vault-env.sh` for all four Sentry values, so a vault missing any of them stops the build instead of shipping an app that reports nothing.

`app.config.ts` treats Sentry as optional: the plugin is added only when a token exists, and `initSentry` returns without a DSN. That keeps development runs and type checks free of Sentry. A store build is different, because a missing value would ship without crash reports or readable traces, and the gap would surface during an incident. A fork without a Sentry project exports the four names itself, or drops them from the build scripts' lists.

The organization is shared with the web build and read from `SWAY_SENTRY_ORG`. The project and the token have mobile-only items. The web project item is `SWAY_SENTRY_PROJECT`, and an item name may not contain another's, so the mobile one is `SWAY_MOBILE_SENTRY_PROJECT`. Both builds read the token through the same `SENTRY_AUTH_TOKEN` name because `sentry-cli` fixes it, and never in the same process: the web token is extracted inside the Kamal deploy and the mobile one is scoped to the `eas build` command. The item list is in [[settings-and-secrets#Mobile Sentry credentials]].
