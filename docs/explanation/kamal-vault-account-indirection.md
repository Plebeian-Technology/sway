---
mode: explanation
summary: "Explains why the account that signs in to the password vault must never appear as a literal in .kamal/secrets-common, and the shell-quoting and word-splitting traps that make checking it non-trivial."
status: agent-extracted
related: []
---

# Why `.kamal/secrets-common` must never name the vault account literally

The account that signs in to the password vault must never be written into
the repository. Sway is a public project, and that account holds every
production credential, so naming it tells a reader exactly which account to
go after. `--account` must always read a variable such as
`$SWAY_BW_ACCOUNT`, never a literal value.

The repo's pre-commit hook already refuses a literal on the LEFT of an
assignment, but it cannot see a literal riding inside the VALUE of
`$(kamal secrets fetch ... --account some-literal ...)` — that shape needed
its own check, `spec/config/kamal_vault_account_spec.rb`.

## Why an empty account must fail the same way as a missing one

`mise.toml` defines `SWAY_BW_ACCOUNT` for every shell in the project and
leaves it EMPTY when `.env.kamal` is absent, which is exactly what a fresh
clone looks like. `printenv` alone succeeds on an empty value, so an empty
`SWAY_BW_ACCOUNT` cannot be left to fall through silently — the resolution
in `.kamal/secrets-common` has to turn "empty" into the same loud fallback
as "unset", otherwise `--account` would silently take the NEXT word on the
command line, which is a secret name, as the account.

## Why the account variable is resolved on its own line, not nested inside the fetch

Kamal does not run a `kamal secrets` line through a shell — it splits the
line into words and calls itself directly. A nested `$(...)` inside the
`--account` argument therefore never gets shell-expanded; it arrives as
the literal word `"$(printenv"` and becomes the account name outright.
Measured against kamal 2.12.0. This is why `SWAY_BW_ACCOUNT` is resolved
on its own line first (`SWAY_BW_ACCOUNT=$(...)`) and referenced as a plain
`$SWAY_BW_ACCOUNT` on the `SECRETS=` fetch line, never inlined as a nested
subshell.
