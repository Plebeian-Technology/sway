#!/usr/bin/env bash
# Tell docker compose where the real .env files are. Invoked from dip.yml and
# from the other scripts/dip entry points.
#
# @lat: [[run-the-stack#Working in a phase worktree]]

set -eu

repo_root="$(git rev-parse --show-toplevel)"

# --git-common-dir names the MAIN checkout's .git even when this runs inside a
# worktree, which is the only reliable way back to where the keys are kept.
common_dir="$(cd "$repo_root" && cd "$(git rev-parse --git-common-dir)" && pwd)"
secrets_root="$(dirname "$common_dir")"

env_file="$repo_root/.dockerdev/.env"
deploy_config="$secrets_root/deploy/config/sway.env"

if [ ! -f "$secrets_root/.env.test" ]; then
    echo "[secrets-root] $secrets_root holds no .env.test — dip runs will fail there." >&2
fi

# @lat: [[run-the-stack#Working in a phase worktree]]
lines="SWAY_SECRETS_ROOT=$secrets_root"
if [ -f "$deploy_config" ]; then
    lines="$lines
SWAY_DEPLOY_CONFIG_SRC=$deploy_config"
else
    echo "[secrets-root] $deploy_config is missing — rake tasks stop at SwayDeployConfig::MissingValue." >&2
fi

# Source and target are the same absolute path.
# @lat: [[run-the-stack#Git inside a worktree's container]]
lines="$lines
SWAY_GIT_COMMON_SRC=$common_dir
SWAY_GIT_COMMON_AT=$common_dir"

ours='^SWAY_SECRETS_ROOT=\|^SWAY_DEPLOY_CONFIG_SRC=\|^SWAY_GIT_COMMON_SRC=\|^SWAY_GIT_COMMON_AT='

if [ -f "$env_file" ] && [ "$(grep "$ours" "$env_file" || true)" = "$lines" ]; then
    exit 0
fi

# Replace only our own lines, so anything else somebody keeps here survives.
kept=""
if [ -f "$env_file" ]; then
    kept="$(grep -v "$ours" "$env_file" || true)"
fi

{
    if [ -n "$kept" ]; then printf '%s\n' "$kept"; fi
    printf '%s\n' "$lines"
} >"$env_file"

if [ "$secrets_root" != "$repo_root" ]; then
    # @lat: [[run-the-stack#Working in a phase worktree]]
    echo "[secrets-root] worktree run — .env files and deploy/config/sway.env read from $secrets_root"
    echo "[secrets-root] no config/master.key here, so Rails credentials read as absent"
fi
