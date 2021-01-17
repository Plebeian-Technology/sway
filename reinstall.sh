#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

echo "####################################################"
echo "TYPES"
echo "####################################################"
cd ${packages}/types
rm -rf node_modules package-lock.json
npm i

echo "####################################################"
echo "CONSTANTS"
echo "####################################################"
cd ${packages}/constants
rm -rf node_modules package-lock.json
npm i
npm run build

echo "####################################################"
echo "FIRE"
echo "####################################################"
cd ${packages}/fire
rm -rf node_modules package-lock.json
npm i
npm run build

echo "####################################################"
echo "WEBAPP"
echo "####################################################"
cd ${packages}/webapp
rm -rf node_modules package-lock.json
npm i

echo "####################################################"
echo "SEEDS"
echo "####################################################"
cd ${packages}/seeds
rm -rf node_modules package-lock.json
npm i

echo "####################################################"
echo "SCRIPTS"
echo "####################################################"
cd ${packages}/scripts
rm -rf node_modules package-lock.json
npm i

echo "####################################################"
echo "FUNCTIONS"
echo "####################################################"
cd ${packages}/functions
rm -rf node_modules package-lock.json
npm i

cd ${working}

# echo "bootstrap"
# npx lerna bootstrap