#!/usr/bin/env bash

set -eu

if [ -f ../apple/application-distribution/.env ]; then
    echo "distribute.sh - .apple.env file found - exporting vars"
    cp ../apple/application-distribution/.env .apple.env
    sed -i '' '/^#/d' .apple.env
    export $(cat .apple.env | xargs)
    rm .apple.env
else
    echo "distribute.sh - no .apple.env file found."
fi

echo ""
echo "distribute.sh - tauri - building for macos arm 64 - m1 macs"
echo ""

REACT_APP_TAURI=1 \
CI=true \
tauri build \
    --target aarch64-apple-darwin \
    --verbose

echo ""
echo "distribute.sh - tauri - building for macos x86_64 - intel macs"
echo ""

REACT_APP_TAURI=1 \
CI=true \
tauri build \
    --target x86_64-apple-darwin \
    --verbose