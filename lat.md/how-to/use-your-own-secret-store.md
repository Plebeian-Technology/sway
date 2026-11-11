---
lat:
  mode: how-to
---
# Use your own secret store

Point the deploy at a secret store other than Bitwarden, or at plain environment variables. The settings are listed in [[settings-and-secrets#Secret store settings]]; a setup that sets none of them keeps using Bitwarden.

## Use another Kamal adapter

Any store that `kamal secrets fetch` supports works, because [[scripts/lib/secrets.sh]] only chooses the adapter and its options.

1. Create one item per name on the `SECRETS=` line of `.kamal/secrets-common`, each named exactly as listed. Add `LITESTREAM_GCS_SERVICE_ACCOUNT_JSON` and `LITESTREAM_GCS_READER_JSON` for backups, and the `SWAY_EXPO_*`/`SWAY_EAS_PROJECT_ID` items for mobile builds.
2. Add the adapter to `.env.kamal`, for example `SWAY_SECRETS_ADAPTER=1password`.
3. Add `SWAY_SECRETS_ACCOUNT=<account>` to `.env.kamal` if the adapter takes one, and `SWAY_SECRETS_FROM=<vault or folder>` if it needs one (1Password `Vault/Item`, Doppler `project/config`).
4. Sign in to the store's own command-line tool the way its Kamal adapter expects.
5. Run `kamal secrets print > /dev/null` from the repository root and confirm it exits without an error; without the redirect it prints every value.
6. Deploy with `scripts/deploy.sh` as usual.

## Run without a vault

The `env` adapter reads each item from the environment variable of the same name, for a fork that keeps its secrets somewhere Kamal has no adapter for.

1. Add `SWAY_SECRETS_ADAPTER=env` to `.env.kamal`.
2. Export every item name on the `SECRETS=` line of `.kamal/secrets-common` in the deploying shell, for example `export SWAY_TWILIO_AUTH_TOKEN=...`. Keep the item names, not the names the app reads.
3. Run `kamal secrets print > /dev/null` from the repository root. A missing variable stops it, and the error names every one that is unset.
4. Deploy with `scripts/deploy.sh` as usual.
