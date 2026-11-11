#!/usr/bin/env sh
# Secret scanning wrapper around gitleaks. Called by the husky pre-commit and
# pre-push hooks. POSIX sh (husky runs hooks via `sh -e`).
#
# Usage:
#   bin/secret-scan.sh staged            # scan staged changes  (pre-commit)
#   bin/secret-scan.sh range "A..B"      # scan a commit range  (pre-push)
#
# Config: .gitleaks.toml (auto-discovered).
#
# Deliberate bypass (more discoverable and narrower than `--no-verify`, which
# skips ALL hooks including lint/format):
#   SWAY_SKIP_SECRET_SCAN=1 git commit ...
set -eu

MODE="${1:-staged}"

if [ "${SWAY_SKIP_SECRET_SCAN:-}" = "1" ]; then
  echo "secret-scan: SKIPPED (SWAY_SKIP_SECRET_SCAN=1)" >&2
  exit 0
fi

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "secret-scan: gitleaks not found on PATH — this gate is fail-closed." >&2
  echo "  Install:  brew install gitleaks" >&2
  echo "  Bypass once (deliberate):  SWAY_SKIP_SECRET_SCAN=1 git ..." >&2
  exit 1
fi

# Neutralize the rails_credentials textconv (.gitattributes → `bin/rails
# credentials:diff`). Left alone it (a) boots Rails, which is blocked on the
# host and silently truncates the scan, and (b) would feed DECRYPTED credentials
# to the scanner. Overriding it to `cat` keeps gitleaks on ciphertext and
# Rails-free. Passed via GIT_CONFIG_* so it applies to gitleaks' own git calls.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=diff.rails_credentials.textconv
export GIT_CONFIG_VALUE_0=cat

case "$MODE" in
  staged)
    exec gitleaks git --staged --no-banner --redact=80 .
    ;;
  range)
    RANGE="${2:?range mode requires a git log range, e.g. A..B}"
    exec gitleaks git --no-banner --redact=80 --log-opts="$RANGE" .
    ;;
  *)
    echo "secret-scan: unknown mode '$MODE' (expected: staged | range)" >&2
    exit 2
    ;;
esac
