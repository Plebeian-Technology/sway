#!/usr/bin/env bash
# @lat: [[mobile-expo-config#Deployment identifiers come from the environment#The simulator build uses the dev tunnel when one is configured]]
# Usage: run-ios.sh [expo run:ios options...]
set -euo pipefail

cd "$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"

scripts/xcode-node-env.sh

tunnel_host="${EXPO_PUBLIC_DEV_TUNNEL_HOST:-}"
if [ -z "$tunnel_host" ]; then
    tunnel_host="$(
        . ../deploy/config/load.sh
        sway_load_config
        printf '%s' "${DEV_TUNNEL_HOST:-}"
    )"
fi

if [ -n "$tunnel_host" ]; then
    export EXPO_PUBLIC_DEV_TUNNEL_HOST="$tunnel_host"
    export EXPO_PUBLIC_API_URL="${EXPO_PUBLIC_API_URL:-https://$tunnel_host}"
else
    echo "run-ios: no DEV_TUNNEL_HOST in deploy/config/sway.env; using https://localhost:3333, where passkeys cannot work." >&2
    export EXPO_PUBLIC_API_URL="${EXPO_PUBLIC_API_URL:-https://localhost:3333}"
fi

echo "run-ios: API at $EXPO_PUBLIC_API_URL" >&2
exec scripts/with-vault-env.sh APPLE_BUNDLE_ID -- expo run:ios "$@"
