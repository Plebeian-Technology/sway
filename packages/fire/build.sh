#!/usr/bin/env zsh

echo ""
echo "Building packages/fire - using tsconfig at - $PWD/tsconfig.json - with options:"
echo ""

rm -rf dist && tsc --project $PWD/tsconfig.json --showConfig && tsc --project $PWD/tsconfig.json