# Secret scanning

Three gates keep credentials out of git and out of the production image.
Tooling: **gitleaks** (fast, staged- and range-aware, catches self-issued
secrets) and **trufflehog** (verifies whether a credential is actually live, and
scans image layer contents).

```bash
brew install gitleaks trufflehog
```

Both hooks are **fail-closed**: if gitleaks isn't installed, the commit/push is
blocked with an install hint. Deliberate one-off bypass (narrower than
`--no-verify`, which skips lint/format/typecheck too):

```bash
SWAY_SKIP_SECRET_SCAN=1 git commit ...
SWAY_SKIP_SECRET_SCAN=1 git push ...
```

## The gates

| Gate | Where | What it does |
|------|-------|--------------|
| **pre-commit** | `.husky/pre-commit` → `bin/secret-scan.sh staged` | gitleaks scans the staged diff. Also asserts `.kamal/secrets` holds only `$(...)`/`$VAR` references, never a literal value. |
| **pre-push** | `.husky/pre-push` → `bin/secret-scan.sh range` | gitleaks scans the commit range being pushed — backstop for anything that reached a commit via `--no-verify`, amend, or rebase. |
| **pre-build** | `.kamal/hooks/pre-build` | Before every Kamal build: asserts the production `.dockerignore` still excludes `master.key`/`.env`/`storage`/`keys`, and that no secret-shaped `ARG`/`ENV` bakes a value into a layer. |
| **pre-deploy** | `.kamal/hooks/pre-deploy` | After build, before containers boot: checks the built image for baked secret-shaped `ENV` (warn), and — with `SWAY_DEEP_IMAGE_SCAN=1` — runs a full `trufflehog docker` layer-content scan (fail-closed). |

### Why the image gate lives in Kamal hooks, not a git hook

A commit-time hook can't inspect an image that doesn't exist yet, and
`scripts/deploy.sh` runs `kamal redeploy` (build + push + deploy) directly,
bypassing CI. Kamal's own `pre-build`/`pre-deploy` hooks are the only points
that see the Dockerfile before the build and the image before it boots.

The production image's secret-safety is *structural*: the Dockerfile injects
`RAILS_MASTER_KEY`, `SENTRY_AUTH_TOKEN`, and the Vite keys via BuildKit
`--mount=type=secret`, so they never enter a layer. The pre-build assertions pin
that property so a future edit can't quietly undo it.

## Config

- **`.gitleaks.toml`** — extends the default ruleset, adds a **Twilio auth-token**
  rule (the default Twilio rule keys off the `AC…` SID and misses the 32-hex
  token), and allowlists encrypted credentials + vendored `sorbet/rbi` stubs.
  Auto-discovered by gitleaks at the repo root. There is no baseline file: the
  hooks scan only new diffs, and a full-history scan reports everything it finds.

### The rails_credentials textconv trap

`.gitattributes` maps `config/credentials*.yml.enc` to a `diff=rails_credentials`
textconv that runs `bin/rails credentials:diff`. Left alone during a scan it
(1) boots Rails — blocked on the host, which **silently truncates the scan**, and
(2) would feed *decrypted* credentials to the scanner. `bin/secret-scan.sh`
neutralizes it to `cat` via `GIT_CONFIG_*`. **Always scan with that override** —
the first full scan under-reported (14 findings) until it was applied (47).

## Running a full-history scan

```bash
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.rails_credentials.textconv \
  GIT_CONFIG_VALUE_0=cat gitleaks git --no-banner --redact=80 .
# Live-credential check across all history (verifies against providers):
trufflehog git file://. --results=verified --no-update
```
