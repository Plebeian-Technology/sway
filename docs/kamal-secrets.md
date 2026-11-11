# Kamal Secrets — Sway Production

Secrets are injected into the production container via Kamal and read from a
secret store — Bitwarden by default. See also `config/deploy.yml` for the
complete secrets list. The item names below are the same in any store.

## Choosing the secret store

`scripts/lib/secrets.sh` picks the store from `SWAY_SECRETS_ADAPTER` (default
`bitwarden`; any `kamal secrets` adapter, or `env` for plain environment
variables), `SWAY_SECRETS_ACCOUNT` and `SWAY_SECRETS_FROM`. The steps are in
`lat.md/how-to/use-your-own-secret-store.md`; the settings are listed in
`lat.md/reference/settings-and-secrets.md`.

## Which account

The account is deliberately not written down in this repository. Naming the
account that holds every production credential tells a reader of a public
repository which account to go after.

Put it in `.env.kamal`, which git ignores and `scripts/deploy.sh` loads:

```
SWAY_SECRETS_ACCOUNT=you@example.com
```

With Bitwarden, the older `SWAY_BW_ACCOUNT` still works. Leave both unset and
the deploy stops at the vault sign-in saying `SWAY_SECRETS_ACCOUNT-is-not-set`,
which is the name of the variable you have to set.

A bare `kamal` command run outside `scripts/deploy.sh` does not load
`.env.kamal` itself; `mise.toml` exports these variables from it for every
shell in the project. The runbook for moving to a new host
(`lat.md/how-to/move-to-a-new-host.md`) is written around bare commands.

## Existing Secrets

These secrets are read by the application:

| Secret | Purpose |
|--------|---------|
| `OPEN_STATES_API_KEY` | OpenStates API (Maryland legislators) |
| `CONGRESS_GOV_API_KEY` | Congress.gov API (federal legislators) |
| `ANTHROPIC_API_KEY` | Claude API for bill summaries |
| `API_KEY_HMAC_SECRET_KEY` | Signs and checks the mobile app's bearer tokens |
| `SWAY_PHONE_CACHE_HMAC_SECRET_KEY` (read as `PHONE_CACHE_HMAC_SECRET_KEY`) | Keys the digest that stands in for a phone number in rate-limit cache rows and the SmsVerificationToken entry |

**`API_KEY_HMAC_SECRET_KEY` — do not rotate casually.** The digest stored on an
`api_keys` row is derived from this value, so replacing it makes every issued key
unverifiable and ends every mobile session. Value comes from
`openssl rand -hex 32`.

**`PHONE_CACHE_HMAC_SECRET_KEY` — a separate secret from `API_KEY_HMAC_SECRET_KEY`
on purpose.** Reasoning: `lat.md/explanation/phone-cache-hashing.md`. Rotating it
invalidates every existing rate-limit bucket and any SMS verification token
issued in the last ten minutes — both are harmless to lose, unlike an `api_keys`
row. Value comes from `openssl rand -hex 32`.

## GITHUB_TOKEN

**Purpose:** Allows `RefreshLegislatorsCacheJob` to open GitHub pull requests
containing updated legislator JSON files for human review. Never writes directly
to the production database.

**Required scopes (fine-grained PAT, ASVS V4 least-privilege):**
- `contents: write` — push a branch and commit JSON files
- `pull-requests: write` — open a PR

**Repository scope:** Sway repo only (NOT all repositories).

**Provisioning steps:**

1. Go to https://github.com/settings/personal-access-tokens/new
2. Token type: **Fine-grained personal access token**
3. Resource owner: the account that owns the Sway repo
4. Repository access: **Only select repositories** → select `sway`
5. Repository permissions:
   - Contents: **Read and write**
   - Pull requests: **Read and write**
6. Generate token and save it to Bitwarden as `GITHUB_TOKEN`
7. Confirm `.kamal/secrets` fetches and extracts it: the var must
   appear in the `kamal secrets fetch` item list AND have a matching
   `GITHUB_TOKEN=$(kamal secrets extract GITHUB_TOKEN $SECRETS)` line. There is
   no `kamal secrets set` command — kamal 2.x has only `fetch`/`extract`/`print`;
   the value lives solely in Bitwarden and is resolved at deploy time.

**Security invariants:**
- The token is read via `ENV.fetch("GITHUB_TOKEN")` in `GitHubPrService`
- It is NEVER passed to any logger or Sentry payload
- Branch name is derived from `Date.current.strftime` (no user input)
- The token must be rotated if compromised; scope to the Sway repo only limits blast radius

## GITHUB_REPO

**Purpose:** Provides the `owner/repo` slug that `GitHubPrService` passes to Octokit.
Required in production because the Docker image excludes `.git/` via `.dockerignore`,
so the git-config fallback (`git config --get remote.origin.url`) returns an empty
string and every Octokit call fails.

**Value format:** `owner/repo` — e.g. `Plebeian-Technology/sway`. This is NOT a secret token.

**Why in secrets?** Kamal's `env.secret` is the conventional injection path for
runtime env vars that are not baked into the image at build time. Even though the
repo slug is not sensitive, it varies per deployment and must be set at runtime.

**Provisioning steps:**

1. Determine the correct slug (e.g. `Plebeian-Technology/sway`)
2. Save it to Bitwarden as an item named `GITHUB_REPO`
   whose password field is the slug — `.kamal/secrets` fetches and extracts it
   at deploy time (`kamal secrets set` does not exist)
3. The value is read at container start via `ENV.fetch("GITHUB_REPO")` in
   `app/services/github_pr_service.rb`

## Active Record encryption keys

**Purpose:** the three keys Active Record encryption derives every column key
from. Sway reads them from the environment, not from Rails credentials, because
a fresh clone has no `config/master.key` and credentials
read as absent there. Reasoning:
`lat.md/explanation/active-record-encryption-keys.md`.

| Bitwarden item | Read as |
|----------------|---------|
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | `config.active_record.encryption.primary_key` |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | `config.active_record.encryption.deterministic_key` |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | `config.active_record.encryption.key_derivation_salt` |

**Provisioning steps:**

1. Generate all three values at once:

   ```
   dip run bundle exec rails db:encryption:init
   ```

   It prints a YAML block holding a `primary_key`, a `deterministic_key` and a
   `key_derivation_salt`. Take the three values; discard the YAML wrapper — it
   is the credentials layout, which Sway does not use.

2. Create one Bitwarden item per key, named exactly as the variable is.
3. Nothing else needs changing: `.kamal/secrets-common` already fetches and
   extracts all three, and `config/deploy.yml` already lists them under
   `env.secret`.

**A lost key cannot be recovered.** Every column encrypted under it becomes
permanently unreadable — no fallback, no re-derivation, and a database backup
holds the same ciphertext. Rotation is a re-encryption migration, never an edit
of the value. The salt counts as a third key for this purpose: changing it is
indistinguishable from changing both keys.

## Browser error reporting (build secrets)

`VITE_SENTRY_DSN` holds the browser's Sentry DSN. It is a build secret in
`config/deploy.yml` (`builder.secrets`), mounted by the Dockerfile and read by
Vite while the bundle is built; `app/frontend/sway_utils/sentry.ts` starts
Sentry only when the bundle carries it. `SENTRY_ORG` and `SENTRY_PROJECT` travel
the same way so the build can upload source maps. All three are Bitwarden items
named exactly as the variable. A build without them keeps its source maps and
reports nothing, which is what a preview wants.

## Adding New Secrets

1. Add the env var name to `config/deploy.yml` under `servers.web.env.secret`
2. Add a placeholder to `.env.example` with a comment explaining purpose and scope
3. Document it in this file with scope and provisioning steps
4. Store the value in Bitwarden
5. Wire it in `.kamal/secrets`: add the var name to the `kamal secrets fetch`
   item list and add a matching `<VAR>=$(kamal secrets extract <VAR> $SECRETS)`
   line. The next `kamal deploy` resolves it from Bitwarden — kamal has no
   `secrets set` command (only `fetch`/`extract`/`print`), and a missing vault
   item aborts the deploy in-process (fail-loud).
