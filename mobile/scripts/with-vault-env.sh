#!/usr/bin/env bash
# @lat: [[mobile-expo-config#Deployment identifiers come from the environment]]
# Usage: with-vault-env.sh [VAR ...] -- <command...>   (no VAR list: every VAR below)
set -euo pipefail

names=(EAS_PROJECT_ID EXPO_OWNER APPLE_TEAM_ID APPLE_BUNDLE_ID EXPO_PUBLIC_DEV_TUNNEL_HOST APP_STORE_CONNECT_API_KEY_ID APP_STORE_CONNECT_ISSUER_ID SENTRY_DSN_MOBILE SENTRY_AUTH_TOKEN SENTRY_ORG SENTRY_PROJECT)
items=(SWAY_EAS_PROJECT_ID SWAY_EXPO_OWNER APPLE_TEAM_ID SWAY_BUNDLE_ID SWAY_EXPO_PUBLIC_DEV_TUNNEL_HOST SWAY_APP_STORE_CONNECT_API_KEY_ID SWAY_APP_STORE_CONNECT_ISSUER_ID SWAY_MOBILE_SENTRY_DSN SWAY_SENTRY_AUTH_TOKEN SWAY_SENTRY_ORG SWAY_MOBILE_SENTRY_PROJECT)

wanted=()
if [[ "${1:-}" == "--" || "${1:-}" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
        wanted+=("$1")
        shift
    done
    if [ "$#" -eq 0 ]; then
        echo "with-vault-env.sh: missing -- before the command. Usage: with-vault-env.sh [VAR ...] -- <command...>" >&2
        exit 2
    fi
    shift
else
    wanted=("${names[@]}")
fi

if [ "$#" -eq 0 ]; then
    echo "with-vault-env.sh: no command given. Usage: with-vault-env.sh [VAR ...] -- <command...>" >&2
    exit 2
fi

# @lat: [[mobile-expo-config#Deployment identifiers come from the environment#Local values come from mobile/.env.local]]
env_file="$(dirname "$0")/../.env.local"
if [ -f "$env_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        line="${line#export }"
        if [[ ! "$line" =~ ^[[:space:]]*([A-Z][A-Z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [ -n "${!key:-}" ]; then
            continue
        fi
        for name in ${wanted[@]+"${wanted[@]}"}; do
            if [ "$name" = "$key" ]; then
                if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
                    value="${BASH_REMATCH[1]}"
                fi
                export "$key=$value"
            fi
        done
    done <"$env_file"
fi

missing=()
for name in ${wanted[@]+"${wanted[@]}"}; do
    index=""
    for i in "${!names[@]}"; do
        if [ "${names[$i]}" = "$name" ]; then
            index="$i"
        fi
    done
    if [ -z "$index" ]; then
        echo "with-vault-env.sh: unknown variable $name. Known: ${names[*]}" >&2
        exit 2
    fi
    if [ -z "${!name:-}" ]; then
        missing+=("$index")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    missing_names=()
    missing_items=()
    for i in "${missing[@]}"; do
        missing_names+=("${names[$i]}")
        missing_items+=("${items[$i]}")
    done
    # @lat: [[use-your-own-secret-store]]
    source "$(dirname "$0")/../../scripts/lib/secrets.sh"
    adapter="$(sway_secrets_adapter)"
    if [ -z "$(sway_secrets_account)" ] && sway_secrets_requires_account "$adapter"; then
        echo "with-vault-env.sh: ${missing_names[*]} unset. Export them, or set SWAY_SECRETS_ACCOUNT to read them from the $adapter items ${missing_items[*]}." >&2
        exit 1
    fi
    secrets="$(sway_secrets_fetch "${missing_items[@]}")"
    for i in "${missing[@]}"; do
        export "${names[$i]}=$(sway_secrets_extract "${items[$i]}" "$secrets")"
    done
fi

for name in ${wanted[@]+"${wanted[@]}"}; do
    export "$name"
done

exec "$@"
