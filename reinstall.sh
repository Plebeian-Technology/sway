#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

echo "####################################################"
echo "TYPES"
echo "####################################################"
cd ${packages}/types
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

echo "####################################################"
echo "CONSTANTS"
echo "####################################################"
cd ${packages}/constants
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

echo "####################################################"
echo "UTILS"
echo "####################################################"
cd ${packages}/utils
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

echo "####################################################"
echo "FIRE"
echo "####################################################"
cd ${packages}/fire
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

echo "####################################################"
echo "WEBAPP"
echo "####################################################"
cd ${packages}/webapp
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

echo "####################################################"
echo "SEEDS"
echo "####################################################"
cd ${packages}/seeds
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

echo "####################################################"
echo "SCRIPTS"
echo "####################################################"
cd ${packages}/scripts
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

echo "####################################################"
echo "FUNCTIONS"
echo "####################################################"
cd ${packages}/functions
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${working}
