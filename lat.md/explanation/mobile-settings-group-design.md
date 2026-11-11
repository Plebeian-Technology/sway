---
lat:
  mode: explanation
---

# Design notes for the Mobile settings group

`Sway::Settings::Mobile` declares six names sharing no common prefix (`env_prefix ""`), each read by a different consumer:

- `APPLE_APP_STORE_ID` — the download page's store link
  (`marketing_controller.rb`).
- `MOBILE_MIN_VERSION` / `MOBILE_LATEST_VERSION` — the two build numbers the
  mobile launch endpoint reports, compared as text by the mobile client
  rather than as version numbers.
- `ANDROID_CERT_SHA256_FINGERPRINTS` — the fingerprint list the Android
  app-link file (`assetlinks.json`, via `WellKnownController`) publishes.
- `APPLE_TEAM_ID` / `APPLE_BUNDLE_ID` — the Apple team and bundle ids, read
  by `config/initializers/apns.rb` for the push token and topic and by
  `WellKnownController` for the apple-app-site-association app id. The
  bundle id is also the Android package name `assetlinks.json` publishes,
  because the mobile config uses one value for both platforms —
  [[mobile-expo-config#Deployment identifiers come from the environment]].
  Neither has a default: a fork's build must not claim another team's app,
  so an unset value turns push off and makes the association files answer
  204.
