---
lat:
  mode: explanation
---

# Android app links

`/.well-known/assetlinks.json` is the document Android reads to decide whether the Sway app may claim `sway.vote` links and share passkeys with the site. Its whole content is one list of signing-certificate fingerprints.

## Why the fingerprints are per-installation configuration

The fingerprints name one installation's signing keys, so they live in the ignored `deploy/config/sway.env` as `SWAY_ANDROID_CERT_SHA256_FINGERPRINTS`, not in the tracked deploy file.

A fork builds its app with its own keys. Fingerprints copied from this repository would publish an `assetlinks.json` that vouches for somebody else's app and matches none of the fork's builds. `config/deploy.yml` passes the value through to the app's `ANDROID_CERT_SHA256_FINGERPRINTS` setting and leaves it blank when the key is absent, which takes the empty-list path below rather than stopping the deploy.

## Why an empty list is announced rather than refused

An empty fingerprint list is announced with a warning rather than refusing to boot when `ANDROID_CERT_SHA256_FINGERPRINTS` is unset.

Android parses that document without complaint and then matches zero apps against it, so verification fails with nothing logged, nothing raised and nothing red. A suite that asserts the empty list is served is in the same shape: it reports fine while the thing it covers does nothing.

Refusing to boot would be the wrong correction. In environments without an Android build or store record, a deploy failing over an absent fingerprint would stop a working site for a feature not in use. `config/initializers/android_app_links.rb` therefore warns once at boot, in production only, and never raises.

The guarantee the request spec holds is narrower and still worth holding: a blank setting yields `[]`, never a list holding one empty entry, which the array caster in `lib/sway/settings/mobile.rb` would otherwise produce. That claim is asserted outside production, so the empty list is not pinned as the expected production state. The production side is asserted separately, in `spec/config/android_app_links_initializer_spec.rb`: the warning fires with an empty list, stays quiet once fingerprints are configured, and raises in no environment.
