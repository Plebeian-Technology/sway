---
lat:
  mode: how-to
---
# Submit the mobile app to the stores

Sway's phone app reaches the App Store and Google Play from one operator's machine. Several values cannot exist until the store records do, so the order is fixed: records first, then the values they yield, then builds.

## Steps

The whole run. Each step that needs more than a line has a section of its own below.

1. Confirm both developer accounts: the Apple team whose id is held in the Bitwarden item `APPLE_TEAM_ID`, and a Google Play developer account. Register the bundle id held in the Bitwarden item `SWAY_BUNDLE_ID` (`APPLE_BUNDLE_ID` below) with the Associated Domains capability.
2. Create the App Store Connect record for that bundle id under that team, and the Play Console record for the same package with Play App Signing enabled — that choice cannot be undone.
3. Settle every value under [[submit-the-mobile-app#Values no waiver covers]].
4. Prove the association files answer on both hostnames.
5. Deliver the push credentials, or accept that push to phones stays silent.
6. Close the accessibility precondition, or waive it finding by finding.
7. Fill the four store forms (listing and privacy for Apple, listing and data safety for Google) from your own listing notes; `mobile/store/` is ignored by git for that purpose. Confirm every URL those files name answers, the privacy policy included. Then confirm the `/download` page renders both badges.
8. Build locally and upload to both stores.

## Values no waiver covers

Six values have no substitute and no waiver path, because each needs something only the store side can issue. Verify each from outside rather than from the console that set it.

1. `APPLE_APP_STORE_ID` — the numeric id from App Store Connect → App Information. Until it is set, `Sway::Settings.mobile.apple_app_store_id` reads `<APPLE_APP_ID>`, and `app/views/layouts/_marketing_mobile_badges.html.erb` drops the App Store link rather than emit a dead one. Redeploy after setting it.
2. `ANDROID_CERT_SHA256_FINGERPRINTS` — BOTH the upload key and the Play-signed key, comma-separated colon-delimited hex, written as `SWAY_ANDROID_CERT_SHA256_FINGERPRINTS` in `deploy/config/sway.env`, read from Play Console → Setup → App integrity or from `keytool -list -v -keystore <upload-keystore>`. Check with `curl -s https://sway.vote/.well-known/assetlinks.json | jq '.[0].target.sha256_cert_fingerprints'`, which must return a non-empty array: an empty one is published with only a warning in the boot log and verifies nothing — [[android-app-links]].
3. The App Store Connect record itself, for bundle id `APPLE_BUNDLE_ID` under the team named by `APPLE_TEAM_ID`.
4. The Play Console record itself, for the same id as package name, with Play App Signing on.
5. A real 1024×1024 sRGB PNG at `mobile/assets/store/app-icon-1024.png`. `file mobile/assets/store/app-icon-1024.png` must report `PNG image data, 1024 x 1024`.
6. Official badge artwork at `public/apple-app-store-badge.svg` and `public/google-play-badge.svg`, taken from Apple's marketing guidelines and Google's badge page. The committed vector artwork renders and satisfies the page's own tests.

## Association files on both hostnames

Both platforms open a link only on the exact hostname the app claims, and the app claims `sway.vote` and `app.sway.vote`. One host serving the files is not enough: a link shared on the other opens the browser instead, silently.

1. Confirm the edge forwards `/.well-known/*` to Rails on both names. The Firefox redirect rule already excludes that prefix so the apex keeps answering — [[cloudflare-edge-rules#Redirect rules]]. Any static layer in front of either name must proxy the prefix or serve identical copies.
2. Run `curl -I` for `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json` on both hostnames. Each of the four must return 200 with `Content-Type: application/json` and `Cache-Control: public, max-age=3600`.
3. Confirm the bodies on both hostnames: `.applinks.details[0].appID` equals `<APPLE_TEAM_ID>.<APPLE_BUNDLE_ID>`, from the Bitwarden items `APPLE_TEAM_ID` and `SWAY_BUNDLE_ID`, and `.[0].target.package_name` equals `<APPLE_BUNDLE_ID>`. Either file answering 204 means the server has no bundle id.
4. Validate the Apple document once per hostname with a public AASA validator, and the Android one with Google's statement-list verifier at `https://developers.google.com/digital-asset-links/tools/generator`.
5. Run `adb shell pm get-app-links <APPLE_BUNDLE_ID>` against an installed Android build. It must report `verified` for both hostnames.

## Push credentials

Push to phones runs on two Apple keys and one Firebase service account. Nothing raises while a credential is absent or malformed, so step 8 below is the only thing that tells a healthy stack apart from a silently dark one.

1. On the Apple side, create two keys under Certificates, Identifiers & Profiles → Keys, each with Apple Push Notifications service enabled: one restricted to the Production APNs environment, one restricted to the Development (sandbox) environment. Apple additionally restricts both to the app's bundle id (Topic Specific) rather than Team Scoped, but that half needs no code change — `ApnsClient` already sends the server's `APPLE_BUNDLE_ID` as `apns-topic` on every push. [[apns-key-environment-pairing#Why the key pair is chosen by APNS_ENV]] has why the environment half must not cross. Each `.p8` downloads exactly once and cannot be recovered from the account afterward; Apple allows two active keys per team and neither expires.
2. On the Firebase side, attach Firebase to the existing GCP project named by `SWAY_GCP_PROJECT_ID` in `deploy/config/sway.env` — Firebase console → Add project → select that project, rather than creating a new one — then enable the Cloud Messaging v1 API and generate the service-account key from Project settings → Service accounts → Generate new private key.
3. Register the Android app (package `<APPLE_BUNDLE_ID>`) in that Firebase project and download the resulting `google-services.json`; `mobile/app.config.ts` reads its path from `GOOGLE_SERVICES_JSON`.
4. Base64-encode the three multiline files before they reach Bitwarden — Kamal cannot carry a raw PEM or JSON value into the container intact: `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy` for each Apple `.p8`, the same over the Firebase service-account JSON file. [[multiline-credentials-over-kamal]] has why.
5. Create six Bitwarden login items, value in the password field: `APPLE_TEAM_ID` (the ten-character team id, plain), `SWAY_APNS_PRODUCTION_BASE64` (the production `.p8`, Base64), `SWAY_PRODUCTION_APNS_KEY_ID` (its key id, plain, from the same Apple Keys page), `SWAY_APNS_SANDBOX_BASE64` (the sandbox `.p8`, Base64), `SWAY_SANDBOX_APNS_KEY_ID` (its key id, plain), `SWAY_FCM_SERVICE_ACCOUNT_JSON` (the Base64 service-account key from step 2).
6. Leave the non-secret values in `config/deploy.yml` alone unless they differ from what is already there: `APNS_ENV` (`production`). `FCM_PROJECT_ID` is rendered from `SWAY_GCP_PROJECT_ID` in `deploy/config/sway.env`; `APPLE_TEAM_ID` comes from the vault item of that name and `APPLE_BUNDLE_ID` from the vault item `SWAY_BUNDLE_ID`.
7. List `APPLE_TEAM_ID`, `SWAY_APNS_PRODUCTION_BASE64`, `SWAY_PRODUCTION_APNS_KEY_ID` and `SWAY_FCM_SERVICE_ACCOUNT_JSON` for delivery only after the vault holds them, never before — [[settings-and-secrets#Push notification credentials]] has the delivered shape, and [[settings-and-secrets#Credentials production is not given]] has why that order is not a preference. Leave `SWAY_APNS_SANDBOX_BASE64` and `SWAY_SANDBOX_APNS_KEY_ID` off that list: they stay out of production on purpose and belong in a local `.env` for development-client builds, where sandbox device tokens come from.
8. Confirm the credentials arrived intact: inside the app container, `bin/rails runner 'puts Rails.application.config.apns.enabled, Rails.application.config.fcm.enabled'` must print `true` twice, and the Rails log must carry no `EnvSecret` Base64 error.
9. Announce a Bill of the Month to a real iPhone and a real Android handset. Each must receive the notification, and a tap must open that bill.
10. Confirm the running scheduler loaded `cleanup_revoked_devices` from `config/recurring.yml`: inside the app container, `bin/rails runner 'puts SolidQueue::RecurringTask.where(key: "cleanup_revoked_devices").pluck(:schedule)'` prints `every day at 3am`.

## The accessibility precondition

`mobile/__tests__/accessibility.test.tsx` holds the half a machine can check: roles and labels on interactive elements, and font scaling never disabled anywhere under `mobile/src`. What no static pass sees is a screen reader on real hardware.

1. Install Maestro — a single binary, so Android needs no Mac — and build a development client locally for each platform.
2. Run the flows under `mobile/.maestro/` in the order `mobile/.maestro/README.md` gives. The passkey flows, `voter_login_and_vote.yaml` and `new_user_signup.yaml`, need a real device with biometric hardware and Associated Domains, and the flows that need a signed-in session run after one of them on that same device; `smoke.yaml` runs on a simulator. Skip `deep_link_bill.yaml` and `screenshots.yaml`, which the README marks as not currently working.
3. Sweep iOS with VoiceOver across Home, bills, bill detail, voting, legislators and profile. Every control announces, no focus is trapped, and the skeleton announces "Loading".
4. Sweep Android with TalkBack over the same path.
5. Raise iOS Dynamic Type to XXXL and Android font scale to its maximum, then confirm nothing clips or overflows on Bill of the Month, bill detail, voting, profile and sign-in.
6. Close the real-device sweep as a pass, or waive each finding it leaves open.

A waiver covers one finding: what it is, why the release ships without it, and where the remediation is tracked. A blanket waiver is not a waiver.

## Build and upload

Builds compile and upload from the machine doing the release, and the binary reaches each store directly rather than through Expo's hosted submit service — [[local-store-uploads#Why the binary never passes through Expo]].

`mobile/eas.json` carries no cloud-build field and must not gain one: the free tier covers local builds and updates, and a field like `resourceClass` starts spending credits.

1. Point the runner at your secret store — Bitwarden by default, through `SWAY_BW_ACCOUNT` or `SWAY_SECRETS_ACCOUNT`, and any other store as in [[use-your-own-secret-store]] — and unlock it.
2. Place the App Store Connect API key at `~/.appstoreconnect/private_keys/AuthKey_<key id>.p8`, not in the worktree. The filename is a requirement rather than a convention — [[local-store-uploads#Why altool dictates the key filename]]. A key scoped to App Manager is sufficient; Admin is not needed.
3. Create two Bitwarden login items, value in the password field: `SWAY_APP_STORE_CONNECT_API_KEY_ID` (the key id, which is the middle of that filename) and `SWAY_APP_STORE_CONNECT_ISSUER_ID` (the account-wide UUID at the top of Users and Access → Integrations). No item's name may contain another's — [[settings-and-secrets#Push notification credentials]]. The build also reads `SWAY_MOBILE_SENTRY_DSN`, `SWAY_MOBILE_SENTRY_PROJECT` and `SWAY_MOBILE_APP_AUTH_TOKEN` the same way, plus the existing `SWAY_SENTRY_ORG` — [[settings-and-secrets#Mobile Sentry credentials]].
4. Export the signing material Expo already holds: from `mobile/`, `scripts/with-vault-env.sh APPLE_BUNDLE_ID EAS_PROJECT_ID EXPO_OWNER -- eas credentials`, then the `production` profile, then Credentials.json → Download credentials from EAS to credentials.json, once per platform. It writes `credentials/ios/dist-cert.p12`, `credentials/ios/profile.mobileprovision` and `credentials/android/keystore.jks`, plus a `credentials.json` naming them. `There are no credentials configured for this project on EAS servers` means Expo holds none, and only then is generating replacements right: on Android a fresh keystore is rejected once Play has bound the app to a signing key. [[local-store-uploads#Why signing moved to local credentials]] has the rest.
5. Apple's two-factor prompt inside `eas credentials` can refuse the iOS half. It is not needed: a distribution certificate and an App Store profile made in Apple's Developer portal are equivalent, because iOS binds nothing permanently the way Play does. Export the `.p12` from Keychain Access with its private key included, and save the pair as `credentials/ios/dist-cert.p12` and `credentials/ios/profile.mobileprovision`. Revoke Expo's own certificate if the account is at Apple's limit, since that is the one being replaced.
6. Create Bitwarden items for the passwords, taking each from the generated `credentials.json`: `SWAY_IOS_DIST_CERT_PASSWORD` for iOS, and `SWAY_ANDROID_KEYSTORE_PASSWORD`, `SWAY_ANDROID_KEY_ALIAS` and `SWAY_ANDROID_KEY_PASSWORD` for Android. Then run `pnpm --dir mobile credentials:write`, which replaces the downloaded file with one rebuilt from the vault and narrows the modes `eas` left world-readable — [[local-store-uploads#Why credentials.json is generated, never committed]]. It writes whichever platform's files are present, so one platform can proceed while the other is still being gathered — [[local-store-uploads#Why one platform's material is enough]].
7. Place `mobile/credentials/play-service-account.json`, from a Google Cloud service account granted release access in Play Console → Users and permissions. Everything under `mobile/credentials/` is gitignored and none of it is ever committed.
8. Run `pnpm --dir mobile release:ios` and `pnpm --dir mobile release:android`. Each regenerates `credentials.json`, checks the signing material, builds and uploads, taking its API address from `expo.extra.apiBaseUrl` in `app.json` so a development `.env.local` cannot reach the binary — [[local-store-uploads#Why one script runs the whole release]]. A local iOS build needs `fastlane` and CocoaPods on the PATH, which nothing in this repository installs. The `production` profile in `mobile/eas.json` raises fastlane's `xcodebuild -showBuildSettings` timeout from 3 to 60 seconds, because the default retry budget of about 45 seconds runs out on a busy machine and fails the build with `xcodebuild -showBuildSettings timed out`. `pnpm --dir mobile build:ios` and `build:android` do the build alone, and `release.sh <platform> --skip-build` uploads an artifact already made.
9. Confirm the iOS build appears in App Store Connect → TestFlight and finishes processing. Nothing reaches the public App Store until a version is submitted for review by hand, and the Android half sits on Play's `internal` track; `PLAY_TRACK` names a wider one when that is the intent — [[local-store-uploads#Why the Android default track is internal]].
10. Read Play's pre-launch report on the first uploaded `.aab` before releasing.
11. Set `MOBILE_MIN_VERSION` to the version declared in `mobile/app.config.ts` and `MOBILE_LATEST_VERSION` to the submitted build, then redeploy so the app's own update prompt tells the truth.

Neither upload publishes anything on its own. On iOS that is Apple's pipeline: every build lands in TestFlight processing first, and review is a separate promotion. On Play it is this project's choice of default track. Internal TestFlight testing needs no Apple review; external testers need Beta App Review, which is a human gate at Apple and lighter than full App Store review.
