#!/usr/bin/env zsh

set -eu

cp ../apple/application-distribution/.env .apple.env
sed -i '' '/^#/d' .apple.env
export $(cat .apple.env | xargs)
rm .apple.env

echo ""
echo "tauri - distribute.sh - Building for MacOS ARM 64 - M1 macs"
echo ""

REACT_APP_TAURI=1 \
CI=true \
tauri build \
    --target aarch64-apple-darwin \
    --verbose

# echo ""
# echo "tauri - distribute.sh - Building for MacOS AMD 64 - Intel macs"
# echo ""

# REACT_APP_TAURI=1 CI=true tauri build --target x86_64-apple-darwin --verbose