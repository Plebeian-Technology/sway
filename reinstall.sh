#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

cd ${packages}/types
echo "####################################################"
echo "TYPES - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${packages}/constants
echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

cd ${packages}/utils
echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

cd ${packages}/fire
echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

cd ${packages}/webapp
echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${packages}/seeds
echo "####################################################"
echo "SEEDS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${packages}/scripts
echo "####################################################"
echo "SCRIPTS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${working}/functions
echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${working}
