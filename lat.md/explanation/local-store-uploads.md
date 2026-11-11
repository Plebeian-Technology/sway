---
lat:
  mode: explanation
---
# Local store uploads

Release binaries travel from the operator's machine to Apple and Google directly, rather than through Expo's hosted submit service. That requirement shapes the uploader, the signing material and the vault items this project keeps.

## Why the binary never passes through Expo

`eas submit` is free on every Expo plan, so cost is not what rules it out. Routing is.

Passed a locally built archive, `eas-cli` uploads the file to Expo's own
storage and an Expo worker submits it onward. In `eas-cli` 27.5.0 that is
`build/submit/ArchiveSource.js`, which logs `Uploading your app archive to
EAS Submit`, calls `uploadAppArchiveAsync`, and returns a source whose type
is `gcs` with a bucket key. Expo's own documentation describes submission
only as uploading to the store and does not mention the hop, so the CLI is
the evidence rather than the docs.

A release artifact is the most sensitive thing this project produces: it is
signed with an identity that can publish under Sway's name. Keeping it
machine-to-store removes a third party from the one path where a substituted
binary would be indistinguishable from a real one. `mobile/eas.json`
therefore declares no `submit` profile at all, so that no command can be run
by habit that would reintroduce the hop.

The build keeps `eas build --local`, which compiles on the same machine. It
still reaches Expo's API to resolve the project id, which is metadata rather
than the artifact. Removing even that would mean owning the `xcodebuild`
invocation directly, a larger trade than the routing requirement asks for.

## Why signing moved to local credentials

`credentialsSource` defaults to `remote`, under which Expo holds the
distribution certificate and the Android keystore and hands them to a local
build on demand.

The binary then compiles locally but is signed with an identity held
elsewhere, which leaves the same third party in the part of the path that
matters most.

`mobile/eas.json` sets `credentialsSource: "local"` for both platforms under
the production profile, so signing reads `mobile/credentials.json` and the
files it names. The signing identity and the artifact then live in the same
place, under the same operator.

Credentials that Expo already generated are the ones that belong in those
files. `eas credentials` exports them, and on Android that is not a
preference: once Play has bound an app to a signing key, a freshly generated
keystore is rejected on upload and the binding cannot be undone. Play App
Signing softens this, because Google then holds the app signing key and the
local one is only an upload key it can reset.

## Why credentials.json is generated, never committed

Expo's local-credentials format holds the keystore and certificate passwords
as plaintext fields. There is no indirection in the schema: no environment
variable reference, no path to a secret.

`mobile/scripts/write-credentials-json.sh` therefore writes the file at
release time from four vault items, under `umask 077`, and
`mobile/.gitignore` excludes it by name. The passwords exist on disk only
while a release is in progress, and the tracked tree holds the shape of the
file without ever holding its secrets. The script refuses to write anything
when the signing files it would name are absent, because a `credentials.json`
pointing at missing paths fails deep inside a build with a less legible
error than a missing-file check produces.

## Why altool dictates the key filename

`altool` has no flag for the path to an App Store Connect API key, so the
key's filename is what locates it.

It takes the key id through `--apiKey` and then searches a fixed set of
directories for a file named `AuthKey_<key id>.p8`: `./private_keys`,
`~/private_keys`, `~/.private_keys` and `~/.appstoreconnect/private_keys`.

A key stored under any other name is invisible to it, however correct its
contents. `mobile/scripts/upload-ios.sh` checks for the expected filename
before invoking `altool` and names the symlink that would fix it, because
the failure `altool` reports otherwise describes an authentication problem
rather than a missing file.

This is also why the key does not live in `mobile/credentials/` beside the
signing material: `altool`'s search path is in the operator's home
directory, not the worktree, and one key there serves every app on the
account.

## Why the App Store Connect key is not delivered by Kamal

Every other credential in this project reaches a running container at deploy
time, through `.kamal/secrets-common` and `EnvSecret`
— [[settings-and-secrets#Credentials]].

An App Store Connect key is used at release time, on the releasing
machine, by the uploader. Nothing in the deployed application reads it.
Delivering it would put a credential that can publish to the App Store
inside the production container, widening what a compromised container
reaches for no gain. The key id and issuer id are vault items read by a
local script instead, which is the channel
[[mobile/scripts/with-vault-env.sh]] already established for build-time
values.

The role the key carries is a separate question from how it is delivered.
Uploading a build and managing TestFlight need no more than App Manager.
Admin is required for creating certificates and profiles through the API,
which this project does not do, because the certificate is made by hand in
Apple's portal and exported into `mobile/credentials/`.

## Why the Play uploader uses only the standard library

`mobile/scripts/upload-android.rb` runs outside the Rails bundle, on the
machine cutting the release, so no gem is guaranteed to be installed. It
reaches for nothing beyond `net/http`, `openssl`, `json` and `base64`.

The alternative was fastlane, which would wrap the same API behind a Ruby
gem tree this project does not otherwise carry, or `googleauth`, which is
present in `Gemfile.lock` only as a transitive dependency of the Firebase
work and so is not a dependency this script may rely on. Roughly thirty
lines of standard library replaced both.

## Why the Play upload mints its own access token

Google's upload endpoint takes an OAuth bearer token, and the only
credential on hand is a service-account key file.

`access_token` builds the assertion that key is for: a JSON Web Token signed
RS256 with the service account's private key, naming the `androidpublisher`
scope, exchanged at the token endpoint the key file itself declares in
`token_uri`. Nothing about that is specific to Play, which is why it is
twenty lines rather than a dependency.

## Why the Android default track is internal

An iOS upload lands in TestFlight processing unconditionally, because that
is the shape of Apple's pipeline rather than a choice the uploader makes.
Reaching the public App Store is a later, separate, manual promotion.

Play has no such forced stage: a track is named on upload, and `production`
would release to the world on commit. `TRACK` in
`mobile/scripts/upload-android.rb` therefore defaults to `internal`, the
closest Play analogue to where an iOS upload stops on its own, so that the
two platforms behave alike and neither publishes as a side effect of being
uploaded. `PLAY_TRACK` overrides it when a wider track is the intent.

## Why one platform's material is enough

Expo's local-credentials format takes an `android` key, an `ios` key, or both, and a build reads only the key for the platform it is building.

`mobile/scripts/write-credentials-json.sh` therefore writes whichever
platform's files are present and names the absent one on stderr, rather than
refusing until both exist. The two platforms are recovered by different
routes and so arrive at different times: Android's keystore has to be the one
Play already knows, which means exporting what Expo holds, while an iOS
certificate and profile are replaceable and can be made in Apple's portal in
a browser. Apple's two-factor prompt inside `eas credentials` blocks the
first route for iOS and does not block the second, so the Android half can be
weeks ahead of the iOS half.

It also asks the secret store only for the passwords belonging to a platform
it is actually writing, so a missing iOS password cannot block an
Android-only release.

## Why the script tightens modes it did not set

`eas credentials` writes a downloaded keystore and the `credentials.json`
naming it with the ambient umask, which on a default macOS account is 022 and
leaves both world-readable.

That file is an app signing key, and the JSON beside it holds its passwords
in cleartext. The script therefore removes group and other access from the
credentials directory and from every signing file it is about to name, before
it writes anything. It only ever narrows, never widens, and it stays silent
when the modes are already right, because the common case is a release that
has run before.

## Why export compliance is declared in the config

`eas build` asks whether the app uses only exempt encryption, and then writes the answer into `ios.infoPlist.ITSAppUsesNonExemptEncryption`.

With no `infoPlist` key in `app.config.ts` that write reads a property of
`undefined` and the build dies with `Cannot read properties of undefined
(reading 'ITSAppUsesNonExemptEncryption')`, after the prompt has been answered
and minutes into the run. Declaring the key gives the write somewhere to land.

Recording it also settles the question once rather than per build. App Store
Connect asks the same thing of every upload, and an unanswered build sits in
TestFlight unavailable to testers until somebody notices. `false` is the
accurate answer here: Sway reaches the network over HTTPS and uses the
platform's own passkey and keychain primitives, all of which Apple exempts.
An app that shipped its own cryptography would answer otherwise, and that is a
legal declaration rather than a build setting.

## Why one script runs the whole release

A release is six steps in a fixed order, and three of them fail in ways that only show up much later or not at all.

`mobile/scripts/release.sh` runs them as one command per platform: it
regenerates `credentials.json` from the vault, checks the signing material is
present, builds, and uploads. The checks are the point. A missing
`play-service-account.json` otherwise surfaces after a full Android build; a
`.p12` whose certificate does not match the provisioning profile surfaces as
a code-signing error naming neither; and an `EXPO_PUBLIC_API_URL` left to a
local `.env.local` ships a binary addressed at a development host with
nothing in the build log saying so.

It warns rather than refuses on a dirty working tree, because uncommitted
files in a checkout are often someone else's and a release that blocks on someone else's
uncommitted file helps nobody. The warning records what the build fingerprint
will say.

## Why the release reads its own API address from app.json

Expo loads `.env.local` in every environment except test, so a development
`EXPO_PUBLIC_API_URL` wins over the fallback in `app.config.ts` and is
compiled into a release binary.

The release script therefore sets the variable explicitly rather than hoping
it is unset, and takes the value from `expo.extra.apiBaseUrl` in `app.json`
rather than carrying its own copy. That key is already the committed
production address, so a fork changes one place and both the script and the
app agree. An `EXPO_PUBLIC_API_URL` exported by the caller still wins, which
is what makes a staging build possible without editing anything.

## Why the screenshot flow navigates by deep link

`mobile/.maestro/screenshots.yaml` reaches each screen with a `sway://` link rather than by opening the drawer and tapping its items.

The other flows open the drawer and tap an item by its test id, such as
`drawer-item-legislators`, which `AppDrawer` sets through
`drawerItemTestID`. A `tapOn` by label is unreliable, because it matches
whatever text the matcher finds first, and a page title can carry the same
word as a drawer item. A screenshot run has to land on an exact screen, and
one of them, Past Bills of the Month, is a segment inside the Bills item
rather than an item of its own. The deep-link map in
`mobile/src/navigation/linking.ts` already names every route this needs,
segment included, so one link per screen replaces a chain of taps.

The flow clears the app's state and starts signed out, and a signed-out app
shows only the sign-in screen, so the run does not currently capture the four
screens. The flow also holds no sign-in step, because a passkey ceremony needs
biometric hardware that a simulator lacks. It does need a server holding data:
a released Bill of the Month, legislators and at least one organization.
Against an empty database the asserts fail rather than capturing empty states,
which is the intended behaviour — an empty screenshot is worse than none.

The mobile app carries one palette, generated from the web's default theme,
in a light and a dark variant. There is no theme to select, so a capture is
in the Sway theme by construction.

## Why the iOS upload reads altool's output rather than its exit code

`altool` prints a line beginning `ERROR:` and exits 0, so a shell that trusts the exit status reports a successful release over a build that never left the machine.

That is the failure this project keeps meeting from a different direction:
`ApnsClient` and `FcmClient` returning early on absent configuration, a
malformed Base64 credential decoding to nil, and now an upload. Each one is
silent in the same way, and each one is caught by looking at what the step
actually said rather than at whether it finished.

`mobile/scripts/upload-ios.sh` therefore captures the output, prints it, and
fails on an `ERROR:` line or a `product-errors` key.

## Why the App Store Connect client mints its own token

`altool --list-providers` and `--list-apps` refuse an API key, answering `list-providers does not support APIKey authentication`, so neither can say what a key can reach.

The App Store Connect REST API answers that directly, and reaching it needs a
token the key signs: an ES256 JSON Web Token naming the key id in its header,
the issuer id as `iss`, and `appstoreconnect-v1` as the audience, valid for at
most twenty minutes. `mobile/scripts/asc.rb` builds that and nothing else, on
the standard library alone, for the same reason the Play uploader does: it
runs outside the Rails bundle, on the machine cutting the release.

One wrinkle earns its line of code. OpenSSL signs ECDSA into a DER structure,
while a JWT wants the raw `r` and `s` values concatenated and each padded to
thirty-two bytes. Handing Apple the DER form produces a 401 that reads as a
bad key rather than a bad encoding.

`asc.rb apps` is the diagnostic that distinguishes the two causes of
`Cannot determine the Apple ID from Bundle ID`: an app record that does not
exist, and one the key has not been granted. The second prints an app list
without the bundle id in it.

## Why the upload names the Apple ID rather than the bundle id

`altool --upload-app` resolves a bundle id to an App Store Connect app itself, and that lookup fails with `Cannot determine the Apple ID from Bundle ID` even when the key plainly reaches the app.

`asc.rb apps` proved the access: the same key, the same issuer, listing the
record with its numeric id. So the lookup is `altool`'s own, and no
permission change fixes it. `--upload-package` takes the Apple ID, bundle id
and both version strings directly and performs no lookup at all.

`upload-ios.sh` reads the three bundle values out of the `.ipa`'s own
`Info.plist` and resolves the Apple ID through `asc.rb`, so nothing has to be
configured and nothing can drift from what was actually built. A fork needs
no new vault item for this: its own key resolves its own app.
