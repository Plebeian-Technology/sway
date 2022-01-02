#!/usr/bin/env zsh

CI=${1-"ci"}

if [ "$1" = "ci" ]; then
    echo "Running Prettier CI"
    npx prettier --config .prettierrc --check "**/*.{ts,tsx,js}"
else
    echo "Running Prettier Write"
    npx prettier --config .prettierrc --write "**/*.{ts,tsx,js}"
fi