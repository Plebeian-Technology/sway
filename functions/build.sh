#!/usr/bin/env zsh

echo ""
echo "Building packages/functions - using tsconfig at - $PWD/tsconfig.json - with options:"
echo ""

rm -rf lib && tsc --project $PWD/tsconfig.json --showConfig && tsc --project $PWD/tsconfig.json