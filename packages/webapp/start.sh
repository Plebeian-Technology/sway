#!/usr/bin/env bash

set -eu

APP=${1}

if [[ "$APP" != "app-sway" && "$APP" != "app-widgets" ]]; then
    echo "First argument to start.sh must be an app name, either 'app-sway' or 'app-widgets'"
else
    echo "export * from \"./${APP}\";" > src/index.ts
    HTTPS=true \
    SSL_CRT_FILE=../../.certs/cert.pem \
    SSL_KEY_FILE=../../.certs/key.pem \
    GENERATE_SOURCEMAP=true \
    react-scripts start
fi
