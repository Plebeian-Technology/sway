---
lat:
  mode: explanation
---

# The Expo config file and the mobile type check

`mobile/app.config.ts` decides the bundle identifier, the associated domains, the intent filters and the plugin list. For a long time no check read it, so a wrong value there was only ever found by a build.

## Why native handover happens in an effect, not at module scope

The Places key is handed to the native module inside an effect rather than at
the top of the file.

Top-level code runs while the JavaScript bundle is still being parsed, and on a
cold start the native module registry is not fully resolved by then, so the
call reaches for something that does not exist yet. An effect runs after mount,
which is late enough for the module to be registered. When the native module is
not linked in — such as in Expo Go or a dev build partway through prebuild —
[[mobile/App.tsx#useGooglePlacesInit]] swallows the initialization error so the
address autocomplete falls back to manual address entry.

The entrypoint in [[mobile/index.js]] conversely installs `react-native-url-polyfill` as its first import and attaches no-op `addEventListener` and `removeEventListener` shims onto `global` before any other module runs, because `@rails/actioncable` touches URL and `window` event listener APIs at import time in an environment without a browser `window`.

The build tooling has the mirror-image problem. The Xcode script phases run
with a small search path, so the node binary is not found and the toolchain
falls back to a deprecated search. The supported override is a generated file,
and what goes into it is the lookup rather than the answer: writing one
interpreter's full path there breaks every build the day the version manager
removes that version, and the failure names a missing file rather than a
missing interpreter, because the override is only checked for being empty.

## App root provider and font gating

[[mobile/App.tsx#App]] wraps the navigation container in outer providers and holds rendering until custom fonts finish loading.

[[mobile/src/state/BootstrapContext.tsx#BootstrapProvider]] sits outside the navigator so any screen can call [[mobile/src/state/BootstrapContext.tsx#useBootstrap]] without prop drilling and the initial `/api/v1/bootstrap` fetch starts in parallel with navigator setup. [[mobile/App.tsx#App]] returns `null` until `OpenSans-Light`, `OpenSans-Regular`, and `OpenSans-SemiBold` finish loading so text never flashes in the system font before swapping. A font that fails to load ends the wait the same way a loaded one does: the app renders in the system font, because holding for a font that will never arrive would leave the splash up and the app looking frozen. The native splash screen is told to stay up as the file loads and is hidden once the fonts are in or have failed, because a cold start runs that wait before any React UI exists and the reader would otherwise see a blank screen; unlike the Places key, the hold has to land before the first render, so it cannot wait for an effect. Inside [[mobile/src/state/BootstrapContext.tsx#BootstrapProvider]], [[mobile/App.tsx#PushWiring]] mounts [[mobile/src/hooks/usePushToken.ts#usePushToken]] and [[mobile/src/hooks/useDeepLinkRouter.ts#useDeepLinkRouter]] where session state and the navigator ref are reachable, while [[mobile/src/components/UpdateBanner.tsx#UpdateBanner]] sits above the navigator so update prompts remain visible without blocking navigation.

## What the mobile test environment has to stand in for

The mobile suite runs without a native bridge, so every library that reaches
native code on import is replaced by a stub in one setup file.

Each stub exists because the real module throws in that environment rather than
because the test wants different behaviour: the animation runtime needs a
native worklets module, the developer-menu module a newer platform version
registers is absent, the network-state poller and the cable client touch native
code as they load, the storage library tries to open a native database, and the
haptics calls have nothing to call. Screens rendered directly, outside a
navigation container, need the navigation hooks stubbed for the same reason.
Where a library publishes its own mock, that one is used rather than a
hand-rolled stub, because a partial stub breaks the moment one mocked module
calls into another. The gesture library behind the drawer is one such case: it
reaches its native module as it loads and the app root sits inside its root
view, so its own published setup file is loaded for every suite, not only the
ones that render the whole app.

The same pressure shapes the tests themselves. A native action sheet cannot be
tapped, so the locale picker is reduced to a trigger and one button per locale;
the platform's own event API is spied on as the file loads rather than mocked
wholesale, so every example below sees the spy.

The crawler is Jest's own rather than the file watcher, because where the
operating system withholds the watcher's state directory it raises before the
first test and the run reads as a broken suite rather than a broken machine.
That setting lives in the config rather than in a package script so a bare
invocation is covered too.

## Why the config file sits inside the type-checked program

`mobile/tsconfig.json` lists what `tsc --noEmit` reads, and `app.config.ts` was in none of the listed roots.

That left the one file the whole build matrix depends on outside every gate, while much smaller files under `src/` were covered. The file is named in `include` now, so the mobile typecheck lane reads it.

## Why the type check tolerates a `.ts` import extension

`app.config.ts` imports its deep-link list with an explicit `.ts` extension, which the Expo CLI requires and `tsc` rejects by default.

The extension is load-bearing: Expo transpiles only the entry file and hands the result to Node, which then resolves that import against the real filesystem and finds no `.js` sibling. Dropping the extension breaks `expo prebuild`, `expo run:*` and `eas build --local` before they do any work.

Pulling the file into the program therefore forced a choice between the extension and the type check. `allowImportingTsExtensions` keeps both: it is sound here because the mobile package never emits JavaScript from `tsc` — Metro and Babel build the app, and TypeScript's requirement that `noEmit` accompany the flag is already satisfied by `expo/tsconfig.base`, which the file extends. It is the one option `mobile/tsconfig.json` has to state for itself; restating the inherited `noEmit` beside it buys nothing.

## New Architecture is not a config key on Expo 55

`newArchEnabled: true` was set in the config and is not a key `@expo/config-types` 55 declares anywhere.

React Native 0.82 ships only the New Architecture, so the field left the schema when the old one was removed and no installed Expo JavaScript reads it. Removing it changes nothing an Expo command can observe — `expo config --type public` resolves the same document with the key gone — and it removes a value a reader would otherwise take as a live switch.

`mobile/android/gradle.properties` does carry `newArchEnabled=true`, which does not contradict this: that directory is written by `prebuild` and is not in the repository, so it records what the generator wrote rather than what the config asked for.

## Why each platform block extends the static config

`app.config.ts` builds the `ios` and `android` objects, and `app.json` is where `autoIncrement` records the build number and version code between releases.

An object literal replaces rather than merges, so a block written from scratch
dropped `ios.buildNumber` and `android.versionCode` on every resolve. The
build then carried `CFBundleVersion` 1 however many times `autoIncrement` had
raised the number, because it was raising a value nothing read.

The failure is invisible until the second upload. App Store Connect accepts
the first build and refuses every later one for a bundle version that did not
increase, and Play refuses a repeated version code the same way. Each block
therefore spreads the static config first and overrides only the keys it
owns.

## Deployment identifiers come from the environment

The Apple team id, the Expo account that owns the project and the EAS project id are read from `APPLE_TEAM_ID`, `EXPO_OWNER` and `EAS_PROJECT_ID` rather than written into `app.config.ts`, `app.json` or `eas.json`.

The three name one deployment's accounts, not the app. A fork that cloned them would build against an Apple team and an EAS project it cannot sign into, and the failure would surface late, at signing or upload. Left unset, each key is simply absent from the resolved config: EAS then uses the signed-in account, or asks for the team. The development error-collector address follows the same rule — `RUSTRAK_DSN_MOBILE` supplies it and `app.json` no longer carries a local default. The production address follows it: `SENTRY_DSN_MOBILE` supplies that one, with the three values the source-map upload needs — [[mobile-sentry-init-design#Why the store build requires the Sentry values]]. The server reads the same `APPLE_TEAM_ID` name — [[mobile-settings-group-design]].

The bundle identifier and the development tunnel host follow the same rule, through `APPLE_BUNDLE_ID` and `EXPO_PUBLIC_DEV_TUNNEL_HOST`. [[mobile/scripts/with-vault-env.sh]] is the one place the maintainer's values enter: it exports each name it is asked for, keeps any value already set, takes what it can from `mobile/.env.local`, and reads the rest from Bitwarden in a single fetch. A caller names only the variables its command needs, so a development run does not demand the EAS ids a store build does. A fork without that vault exports the variables itself and the runner fetches nothing.

### Why a missing bundle id stops the config

With `APPLE_BUNDLE_ID` unset, resolving the config throws an error that names the variable and the runner, rather than falling back to a default id.

A build with no bundle id is meaningless, and a default would be another deployment's app: a fork would sign, link and push against an identifier it does not own, and find out at upload. Every package script that resolves the config therefore goes through the runner. Type checking and linting never execute the file, so they need no value; the config test sets a neutral one.

### Local values come from mobile/.env.local

Before it asks the secret store, the runner reads `KEY=value` lines from the gitignored `mobile/.env.local` for the names its caller asked for. A value already exported still wins.

A development run needs only the bundle id, which is not secret, so unlocking a vault for it on every simulator build is friction with no benefit. Writing the id into a package script instead would put the maintainer's identifier back in the tracked tree. The file stays on one machine, and Expo already loads it into the app config, so one file serves both. Only names the caller requested are taken, and any name the file lacks still comes from the secret store, so a store build is unchanged.

### The dev tunnel host is claimed only when set

With `EXPO_PUBLIC_DEV_TUNNEL_HOST` unset, the developer-mode associated domains and the matching Android intent filter are left out; the `sway.vote` entries stay.

Apple and Google bind associated domains to an exact host, so a contributor's own tunnel must be claimed or passkeys and deep links fail silently there. A built-in fallback host would instead claim the maintainer's tunnel in every fork. The Rails side reads the same host as `DEV_TUNNEL_HOST` — [[well-known-controller-notes#Why the dev tunnel host is appended only in development]]. The development scripts build `EXPO_PUBLIC_API_URL` from it, so the app and its links point at one host.
