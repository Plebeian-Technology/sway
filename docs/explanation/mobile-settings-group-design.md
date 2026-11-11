---
mode: explanation
summary: "What each of Sway::Settings::Mobile's four names is for and which consumer reads it, since none of them share a common prefix."
status: agent-extracted
related: [settings-group-declaration-notes]
---

<!-- vale Vale.Spelling = NO -->

# Design notes for the Mobile settings group

`Sway::Settings::Mobile` declares four names sharing no common prefix
(`env_prefix ""`), each read by a different consumer:

- `APPLE_APP_STORE_ID` — the download page's store link
  (`marketing_controller.rb`).
- `MOBILE_MIN_VERSION` / `MOBILE_LATEST_VERSION` — the two build numbers the
  mobile launch endpoint reports, compared as text by the mobile client
  rather than as version numbers.
- `ANDROID_CERT_SHA256_FINGERPRINTS` — the fingerprint list the Android
  app-link file (`assetlinks.json`, via `WellKnownController`) publishes.
