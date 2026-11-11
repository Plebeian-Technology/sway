---
lat:
  mode: explanation
---

# Why .kamal/secrets-common must never name the vault account literally

The account that signs in to the password vault must never be written into the repository.

Sway is a public project, and that account holds every production credential, so naming it tells a reader exactly which account to go after. The account comes from `SWAY_SECRETS_ACCOUNT` (or, for Bitwarden, `SWAY_BW_ACCOUNT`) in the ignored `.env.kamal`, and reaches `--account` only through [[scripts/lib/secrets.sh]] at deploy time.

The repo's pre-commit hook already refuses a literal on the LEFT of an assignment, but it cannot see a literal riding inside the VALUE of `$(kamal secrets fetch ... --account some-literal ...)` — that shape needed its own check, `spec/config/kamal_vault_account_spec.rb`.

## Why an empty account must fail the same way as a missing one

`mise.toml` defines `SWAY_BW_ACCOUNT` and `SWAY_SECRETS_ACCOUNT` for every shell in the project and leaves them EMPTY when `.env.kamal` is absent, which is exactly what a fresh clone looks like.

An empty account cannot be left to fall through silently: `--account` with nothing after it would take the NEXT word on the command line, which is a secret name, as the account. The helper therefore turns "empty" into the same loud placeholder as "unset", `SWAY_SECRETS_ACCOUNT-is-not-set`, so the vault sign-in fails naming the variable to set. Adapters that take no account get no `--account` at all.

## Why the account variable is resolved on its own line, not nested inside the fetch

Kamal does not run a `kamal secrets` line through a shell — it splits the line into words and calls itself directly.

A nested `$(...)` inside the fetch line therefore never gets shell-expanded; it arrives as the literal word `"$(printenv"` and becomes an argument outright. Measured against kamal 2.12.0. This is why the whole fetch command is resolved on its own line first (`SWAY_SECRETS_FETCH=$(bash scripts/lib/secrets.sh fetch-command)`, which a real shell runs) and referenced as a plain `$SWAY_SECRETS_FETCH` at the start of the `SECRETS=` line.

## Why the helper prints the fetch command instead of running it

Kamal substitutes `$SWAY_SECRETS_FETCH` before it looks at the command, so for every vault adapter the `SECRETS=` line still begins `kamal secrets fetch` and still runs inside Kamal's own process.

That keeps the property the rest of the file relies on: a failed fetch raises inside Kamal and aborts the deploy before an empty value ships. Had the helper run the fetch itself, the line would go through a shell whose failure Kamal ignores. The maintainer's Bitwarden deploy runs the exact command it ran before the helper existed.

The `env` adapter has no Kamal adapter, so its command is the helper's `fetch-inline`, which does run in a shell. To stay fail-closed it prints a word that is not JSON when a variable is missing, and every following `kamal secrets extract` then raises on it.
