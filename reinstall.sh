#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

echo "types"
cd ${packages}/types
rm -rf node_modules package-lock.json
npm i

echo "constants"
cd ${packages}/constants
rm -rf node_modules package-lock.json
npm i
npm run build

echo "fire"
cd ${packages}/fire
rm -rf node_modules package-lock.json
npm i
npm run build

echo "webapp"
cd ${packages}/webapp
rm -rf node_modules package-lock.json
npm i

echo "seeds"
cd ${packages}/seeds
rm -rf node_modules package-lock.json
npm i

echo "functions"
cd ${packages}/functions
rm -rf node_modules package-lock.json
npm i

cd ${working}

# echo "bootstrap"
# npx lerna bootstrap