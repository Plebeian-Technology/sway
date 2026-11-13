# Sway Mobile

The iOS and Android app for [Sway](../README.md), built with [Expo](https://expo.dev) and React Native. It talks to the same Rails backend the web app uses, over a JSON API rather than Inertia.

This is a separate pnpm workspace. Run every command below from the repository root unless noted.

## Prerequisites

- The Rails backend running locally — see [Development](../README.md#development) in the root README. The app defaults to `https://localhost:3333`, which is the Caddy address the dev stack serves.
- Xcode (iOS) or Android Studio (Android) for native builds. `expo start` alone needs neither.

## Running

```zsh
pnpm --dir mobile start          # Metro + dev client, pointed at https://localhost:3333
pnpm --dir mobile run ios        # build and launch on the iOS simulator, through the dev tunnel when DEV_TUNNEL_HOST is set
pnpm --dir mobile run android    # build and launch on an Android emulator
```

Every script that resolves `app.config.ts` needs `APPLE_BUNDLE_ID` — see [Shipping your own build](#shipping-your-own-build). To build without unlocking a secret store, put it in `mobile/.env.local`:

```zsh
printf '\nAPPLE_BUNDLE_ID=%s\n' your.bundle.id >> mobile/.env.local
```

The backend address comes from `EXPO_PUBLIC_API_URL`, which `app.config.ts` reads into `apiBaseUrl` (falling back to `https://app.sway.vote`). The `start` and `android` scripts set it to `https://localhost:3333`; `ios:dev`, `android:dev` and `android:dev:device` point at `https://$EXPO_PUBLIC_DEV_TUNNEL_HOST` instead. `ios` uses `https://$DEV_TUNNEL_HOST` when `deploy/config/sway.env` sets it, and localhost otherwise. Passkeys need the tunnel: iOS cannot associate the app with `localhost`. They also need the dev Rails container to serve the association file, so `.env.development` must set `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID`; without them `https://$DEV_TUNNEL_HOST/.well-known/apple-app-site-association` answers 204 and every passkey ceremony fails with "not associated with domain". To reach a backend somewhere else, set it yourself:

```zsh
EXPO_PUBLIC_API_URL=https://your-host pnpm --dir mobile start
```

## Testing and linting

```zsh
pnpm --dir mobile test           # Jest (TZ=UTC)
pnpm --dir mobile run typecheck  # tsc --noEmit
pnpm lint:mobile                 # oxlint — mobile has its own .oxlintrc.json
```

CI runs the Jest suite on any push that touches `mobile/` (`.github/workflows/mobile-test.yml`).

## Builds

Builds run **locally only** — this project uses free-tier Expo and does not use paid EAS build services:

```zsh
pnpm --dir mobile run build:local   # scripts/with-vault-env.sh eas build --local
```

## Shipping your own build

Nothing in the tree names the maintainer's Apple team, bundle id, Expo account, EAS project or development tunnel. A fork sets these in its own environment instead:

| Variable | Read by | Value |
| --- | --- | --- |
| `APPLE_TEAM_ID` | `mobile/app.config.ts` (`ios.appleTeamId`) and the Rails server (`Sway::Settings.mobile.apple_team_id`) | Your ten-character Apple Developer team id |
| `APPLE_BUNDLE_ID` | `mobile/app.config.ts` (`ios.bundleIdentifier`, `android.package`; required) and the Rails server (`Sway::Settings.mobile.apple_bundle_id`): APNs topic, the apple-app-site-association app id and the `assetlinks.json` package name | Your bundle identifier, used on both platforms |
| `EXPO_OWNER` | `mobile/app.config.ts` (`owner`) | Your Expo account or organization; unset uses the signed-in account |
| `EAS_PROJECT_ID` | `mobile/app.config.ts` (`extra.eas.projectId`) | The id `eas init` prints for your project |
| `RUSTRAK_DSN_MOBILE` | `mobile/app.config.ts` (`extra.rustrakDsn`) | Optional development error collector; unset keeps errors in the console |
| `EXPO_PUBLIC_DEV_TUNNEL_HOST` / `DEV_TUNNEL_HOST` | The app (developer-mode associated domains, the `*:dev` scripts' API address) and the dev stack | Your development tunnel host; unset claims none |
| `APP_STORE_CONNECT_API_KEY_ID` | `mobile/scripts/asc.rb` and `upload-ios.sh` | The key id in your `AuthKey_<id>.p8` filename |
| `APP_STORE_CONNECT_ISSUER_ID` | the same two | The account-wide UUID from Users and Access, Integrations |

`mobile/scripts/with-vault-env.sh [VAR ...] -- <command...>` runs a command with these variables set; with no list it sets all seven below. Any you already exported win, then any set as `KEY=value` lines in the gitignored `mobile/.env.local`; the rest it reads in one fetch from the secret store `scripts/lib/secrets.sh` selects — Bitwarden by default, through the account named by `SWAY_SECRETS_ACCOUNT` or `SWAY_BW_ACCOUNT`. With no account and a variable missing, it stops and names both. A fork without that vault exports the variables itself.

| Variable | Bitwarden item |
| --- | --- |
| `EAS_PROJECT_ID` | `SWAY_EAS_PROJECT_ID` |
| `EXPO_OWNER` | `SWAY_EXPO_OWNER` |
| `APPLE_TEAM_ID` | `APPLE_TEAM_ID` |
| `APPLE_BUNDLE_ID` | `SWAY_BUNDLE_ID` |
| `EXPO_PUBLIC_DEV_TUNNEL_HOST` | `SWAY_EXPO_PUBLIC_DEV_TUNNEL_HOST` |
| `APP_STORE_CONNECT_API_KEY_ID` | `SWAY_APP_STORE_CONNECT_API_KEY_ID` |
| `APP_STORE_CONNECT_ISSUER_ID` | `SWAY_APP_STORE_CONNECT_ISSUER_ID` |

`build:local` and `submit` ask for all six; `start`, `ios`, `android` and `prebuild` ask only for `APPLE_BUNDLE_ID`; the `*:dev` scripts add `EXPO_PUBLIC_DEV_TUNNEL_HOST`.

In production the server gets `APPLE_TEAM_ID` from the Bitwarden item of that name through `.kamal/secrets-common`, and `APPLE_BUNDLE_ID` from the Bitwarden item `SWAY_BUNDLE_ID`. With either unset, push to iPhones stays off and `/.well-known/apple-app-site-association` answers 204; with no bundle id, `/.well-known/assetlinks.json` answers 204 too.

## How it talks to Rails

`src/api/client.ts` is the single HTTP entry point. It sends a bearer token (`Authorization: Bearer <token>`) held in `src/auth/tokenStore.ts`, and every endpoint is declared in `src/api/routes.ts` under `/api/v1` — for example `/api/v1/bootstrap` for initial app state. Authentication mirrors the web app: passkeys (`src/auth/passkeyAuth.ts`) with SMS verification during registration (`src/auth/smsAuth.ts`).

The rest of `src/` is organized by concern: `screens/` and `navigation/` for the UI shell, `components/` for shared pieces, `state/` and `cache/` for client state, `channels/` for ActionCable subscriptions, and `theme/` for styling (NativeWind).

## Design parity

Native patterns win over pixel-matching the web app where the two conflict; divergences are tracked in [`docs/sway-visual-alignment.md`](docs/sway-visual-alignment.md), with supporting screenshots under [`docs/parity-evidence/`](docs/parity-evidence).
