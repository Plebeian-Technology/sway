#!/usr/bin/env zsh

echo ""
echo "Building packages/functions - using tsconfig at - $PWD/tsconfig.json - with options:"
echo ""

# Remove old code
rm -rf lib

# Log options passed to tsc
tsc --project $PWD/tsconfig.json --showConfig

# Build from tsconfig.json
tsc --project $PWD/tsconfig.json

# Copy geojson files to lib/geojson
mkdir -p $PWD/lib/geojson/
cp -r $PWD/src/geojson/* $PWD/lib/geojson/