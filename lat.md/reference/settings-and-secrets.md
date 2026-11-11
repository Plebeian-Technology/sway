---
lat:
  mode: reference
---
# Settings and secrets

Configuration reaches the application through exactly two doors: `Sway::Settings` for declared settings, and `EnvSecret` for credentials. No file under `app/` reads `ENV` directly, and a lint gate enforces that.

## Settings groups

Each group is an `Anyway::Config` subclass under `lib/sway/settings/`, read as `Sway::Settings.<group>.<name>`. Every setting is declared with a type and, unless genuinely required, a default.

- `base` — not settings: the shared superclass and the type-caster registry
- `dev_login` — development account seed values and `skip_phone_verification`
- `legislation` — pipeline artifact roots under `LEGISLATION_ROOT`, plus `tessdata_prefix`
- `llm` — provider, llama.cpp base URL and model, request timeout, source and testimony size caps
- `mobile` — App Store id, minimum and latest app versions, Android cert fingerprints, Apple team and bundle ids, the hosts that serve the app association files (`APP_ASSOCIATION_HOSTS`)
- `ops` — SMS phone number, deploy stamp, backup skip flag, Docker detection, dev tunnel host
- `rate_limits` — per-endpoint switches for sign-in, sign-up, verification, invites, push and bootstrap
- `upstream` — base URLs for Legistar, OpenStates, congress.gov, Wikidata, Open Baltimore, law XML, Open Legislator, Brave Search
- `webauthn` — allowed origins, relying-party id, and the hosts that serve `/.well-known/webauthn` (`WEBAUTHN_RELATED_HOSTS`)

## Type casters

`Sway::Settings::Base` overrides the default `Anyway::TypeRegistry` casters, because the stock ones misread values that appear in real configuration.

- `string` — stripped; empty reads as `nil`, so a blank value falls back to the default
- `integer` — parsed base 10 explicitly, since bare `Integer()` reads a leading zero as octal; text that is not a whole number raises `ArgumentError` instead of reading as zero
- `float` — matched against `/\A[+-]?(\d+(\.\d+)?|\.\d+)([eE][+-]?\d+)?\z/` before `Float()` runs, since bare `Float()` reads a leading `0x` as hex; anything outside that format raises `ArgumentError`
- `boolean` — blank reads as `nil`; `true`, `t`, `yes`, `y` and `1` read as `true` whatever their case; other non-blank text reads as `false` rather than raising
- `integer!` and `float!` resolve to the same blocks as their plain spellings
- a value stays text until a declared type moves it: `Base` calls `disable_auto_cast!`

## Credentials

`app/lib/env_secret.rb` is the only path in the application permitted to read `ENV`. It exposes two entry points.

- `EnvSecret.read(name)` — returns the value, or `nil` when absent
- `EnvSecret.fetch!(name)` — raises when the credential is absent
- [[app/lib/env_secret.rb#EnvSecret#brave_search_api_key!]] — raises when `BRAVE_SEARCH_API_KEY` is absent
- [[app/lib/env_secret.rb#EnvSecret#open_states_api_key!]] — raises when `OPEN_STATES_API_KEY` is absent
- [[app/lib/env_secret.rb#EnvSecret#congress_gov_api_key!]] — raises when `CONGRESS_GOV_API_KEY` is absent

## Phone lists that decide access

Two credentials are lists of phone numbers, and each grants something by membership. Both travel the Kamal secret path: named under `env.secret` in `config/deploy.yml`, fetched and extracted in `.kamal/secrets-common`.

- `ADMIN_PHONES` — the numbers `User#is_admin?` accepts
- `API_USER_PHONES` — the numbers allowed to mint an API key, added to both lists when the mobile API keys landed
- The vault items are `SWAY_ADMIN_PHONES` and `SWAY_API_USER_PHONES`, extracted into the unprefixed variables
- A `SWAY_API_USER_PHONES` item must exist in the vault before the next deploy: `kamal secrets fetch` raises on a name it cannot find, and the deploy aborts before anything ships
- An empty list in production is not the intent for either name — it reads as "nobody", silently, which is the state `API_USER_PHONES` was in while it reached the container by no route

## Credentials production is not given

Some names the application reads are deliberately not delivered. `EnvCredentialScanner::UNDELIVERED_CREDENTIALS` holds that set with one reason each, and `spec/config/deploy_yml_spec.rb` fails on a credential in neither place.

- `SWAY_DATABASE_PASSWORD`, and the APNs sandbox key pair, which production never reads
- The names are absent from `config/deploy.yml` on purpose: Kamal looks up every listed name at deploy time and fails on one the vault does not hold, so the vault entries come first and the lists second

## Push notification credentials

Push to phones takes five vault-held credentials, two of which never reach production, one vault-held identifier, and three plain values. Browser push is a separate, already-provisioned mechanism (`VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`).

- The production Apple key pair: Bitwarden items `SWAY_APNS_PRODUCTION_BASE64` (the `.p8`, strict Base64) and `SWAY_PRODUCTION_APNS_KEY_ID` (single-line), mapped by `.kamal/secrets-common`'s `extract` step onto the differently-named env vars `APNS_AUTH_KEY_P8` and `APNS_KEY_ID` — the same renaming pattern `OPEN_ROUTER_API_KEY` uses onto `OPENROUTER_API_KEY`
- The sandbox Apple key pair: Bitwarden items `SWAY_APNS_SANDBOX_BASE64` and `SWAY_SANDBOX_APNS_KEY_ID`, read as `APNS_SANDBOX_AUTH_KEY_P8` and `APNS_SANDBOX_KEY_ID` — absent from `.kamal/secrets-common`'s fetch list and from `EnvCredentialScanner::UNDELIVERED_CREDENTIALS`'s delivered set on purpose; it belongs in a local `.env` for development-client builds, which is where sandbox device tokens come from
- `FCM_SERVICE_ACCOUNT_JSON` comes from Bitwarden item `SWAY_FCM_SERVICE_ACCOUNT_JSON`; it is multiline and travels as strict Base64 the same way as the two Apple `.p8` values, decoded through `EnvSecret.read_base64` — [[multiline-credentials-over-kamal]]
- The three delivered credentials (`APNS_AUTH_KEY_P8`, `APNS_KEY_ID`, `FCM_SERVICE_ACCOUNT_JSON`) are `env.secret` in `config/deploy.yml`, each a Bitwarden login item whose name carries the `SWAY_` prefix and, for the `.p8`, its encoding, renamed onto the variable by the `extract` step, with the value in its password field, fetched and extracted in `.kamal/secrets-common`
- `APPLE_TEAM_ID` is not a credential but is kept out of the tracked tree: Bitwarden item `APPLE_TEAM_ID`, fetched in `.kamal/secrets-common` and delivered under `env.secret`; it is read as `Sway::Settings.mobile.apple_team_id` by both `config/initializers/apns.rb` and the apple-app-site-association response
- `APNS_ENV` (`production`) and `FCM_PROJECT_ID` are not credentials and sit under `env.clear` in `config/deploy.yml`; `FCM_PROJECT_ID` is rendered from `SWAY_GCP_PROJECT_ID` in `deploy/config/sway.env`
- With `APPLE_TEAM_ID` or `APPLE_BUNDLE_ID` unset, `config.apns.enabled` is false and `/.well-known/apple-app-site-association` answers 204; neither has a built-in default
- A `FCM_PROJECT_ID` carrying angle brackets reads as absent, so a placeholder leaves `config.fcm.enabled` false rather than addressing a project that does not exist
- `FcmClient.deliver` and `ApnsClient.deliver` still return early and log nothing when configuration is absent — a malformed or missing credential and a healthy one look identical from outside except for the error `EnvSecret.read_base64` logs on a bad Base64 value
- `APPLE_TEAM_ID` carries no `SWAY_` prefix: the team id is not specific to Sway, so its item carries no `SWAY_` prefix
- The `_BASE64` suffix records the encoding in the item name, so the item name says how the key is stored; an item without that suffix holds the unencoded key and is not what this project reads
- [[apns-key-environment-pairing#Why the key pair is chosen by APNS_ENV]] has why production reads only the production pair and never the sandbox one

## Mobile Sentry credentials

The mobile store build reads four Sentry values through `mobile/scripts/with-vault-env.sh`, each from a Bitwarden login item with the value in its password field.

- `SENTRY_DSN_MOBILE` — item `SWAY_MOBILE_SENTRY_DSN`; read by `mobile/app.config.ts` into `extra.sentryDsn`
- `SENTRY_AUTH_TOKEN` — item `SWAY_MOBILE_APP_AUTH_TOKEN`; uploads source maps and debug symbols; the web build uses the same variable name from `SWAY_SENTRY_AUTH_TOKEN`
- `SENTRY_ORG` — item `SWAY_SENTRY_ORG`, shared with the web build
- `SENTRY_PROJECT` — item `SWAY_MOBILE_SENTRY_PROJECT`; not `SWAY_SENTRY_PROJECT`, which names the web project
- Passed by `mobile/scripts/release.sh` and the `build:ios`, `build:android` and `build:local` package scripts
- [[mobile-sentry-init-design#Why the store build requires the Sentry values]] has why all four are required

## Phone cache HMAC secret

`PHONE_CACHE_HMAC_SECRET_KEY` keys the digest [[phone-cache-hashing|PhoneCacheKey]] computes to stand in for a phone number in rate-limit cache rows and the SmsVerificationToken entry, read through `EnvSecret` and kept separate from `API_KEY_HMAC_SECRET_KEY`.

- The value lives in the secret store, in the item `SWAY_PHONE_CACHE_HMAC_SECRET_KEY`, extracted as `PHONE_CACHE_HMAC_SECRET_KEY`
- `.kamal/secrets-common` fetches it and `config/deploy.yml` lists it under `env.secret`, so Kamal pushes it into the running container
- `Rails.env.test?` resolves it to the fixed string `"test"` instead, so specs never need the real value
- An absent secret in any other environment raises `PhoneCacheKey::MissingHmacSecretError` the first time a non-blank phone needs hashing

## Active Record encryption keys

Active Record encryption takes three keys, read from the environment in `config/application.rb` through `EnvSecret` and assigned to `config.active_record.encryption`. Rails credentials are deliberately not the source.

- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` — derives the key that protects a non-deterministic column
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` — derives the key for deterministic columns, the ones that stay queryable
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` — salts both derivations
- The values live in Bitwarden, in items named exactly as the variables are
- `.kamal/secrets-common` fetches all three and `config/deploy.yml` lists them under `env.secret`, so Kamal pushes them into the running container
- An absent key leaves that setting unset and boot still succeeds; the failure is deferred to the first read or write of an encrypted column — [[active-record-encryption-keys]]

## Secret store settings

Deploy-side shell settings that choose where `.kamal/secrets-common` and the operator scripts read secrets from. Set in `.env.kamal`; an empty value counts as unset. [[use-your-own-secret-store]] is the recipe.

- `SWAY_SECRETS_ADAPTER` — a `kamal secrets fetch --adapter` name (`bitwarden`, `bitwarden-sm`, `1password`, `lastpass`, `aws_secrets_manager`, `gcp`, `doppler`, `passbolt`, `enpass`) or `env`; default `bitwarden`
- `SWAY_SECRETS_ACCOUNT` — passed as `--account`; with the `bitwarden` adapter it falls back to `SWAY_BW_ACCOUNT`, and no other adapter reads `SWAY_BW_ACCOUNT`
- `SWAY_SECRETS_FROM` — passed as `--from` when set
- Adapters that take no account: `aws_secrets_manager`, `bitwarden-sm`, `doppler`, `enpass`, `passbolt`, `env`; every other adapter gets the placeholder account `SWAY_SECRETS_ACCOUNT-is-not-set` when none is set
- `env` — each item is read from the environment variable of the same name; an unset or empty one fails the fetch
- `mise.toml` exports all three, plus `SWAY_BW_ACCOUNT`, from `.env.kamal`
- [[scripts/lib/secrets.sh]] holds the functions: `sway_secrets_unlock [--sync]`, `sway_secrets_fetch ITEM...` (JSON), `sway_secrets_extract ITEM JSON`, `sway_secrets_get ITEM`, `sway_secrets_fetch_command`
- Bitwarden `sway_secrets_get` reads `bw get password ITEM`; Bitwarden `sway_secrets_unlock` runs `bw unlock --raw` only when `BW_SESSION` is unset or `bw status` is not unlocked
- Callers: `.kamal/secrets-common`, `scripts/deploy.sh`, `scripts/provision-litestream-key.sh`, `mobile/scripts/with-vault-env.sh`

## The enforcement gate

`bundle exec rake sway:lint:env_reads` parses every tracked file under `app/` rather than grepping it, and fails the build on a second direct `ENV` read.

- A new setting is declared in the group it belongs to, or a new group, under `lib/sway/settings/`
- A new credential is read through `EnvSecret`
- A knob that must change without a deploy belongs in `AdminSetting` instead — see [[llm-summaries#Settings live in the database]]
