#!/usr/bin/env zsh

echo ""
echo "Building packages/seeds - using tsconfig at - $PWD/tsconfig.json - with options:"
echo ""

pnpm i ../constants ../utils ../fire

rm -rf dist && tsc --project $PWD/tsconfig.json --showConfig && tsc --project $PWD/tsconfig.json