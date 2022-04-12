#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

rm -rf node_modules package-lock.json
rm -rf \
    ${packages}/types/node_modules \
    ${packages}/types/package-lock.json
rm -rf \
    ${packages}/constants/node_modules \
    ${packages}/constants/package-lock.json
rm -rf \
    ${packages}/utils/node_modules \
    ${packages}/utils/package-lock.json
rm -rf \
    ${packages}/fire/node_modules \
    ${packages}/fire/package-lock.json
rm -rf \
    ${packages}/webapp/node_modules \
    ${packages}/webapp/package-lock.json
rm -rf \
    ${packages}/functions/node_modules \
    ${packages}/functions/package-lock.json
rm -rf \
    ${packages}/seeds/node_modules \
    ${packages}/seeds/package-lock.json
rm -rf \
    ${packages}/scripts/node_modules \
    ${packages}/scripts/package-lock.json

cd ${packages}/types
echo "####################################################"
echo "TYPES - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${packages}/constants
echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

cd ${packages}/utils
echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

cd ${packages}/fire
echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16
npm run build

cd ${packages}/webapp
echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${packages}/seeds
echo "####################################################"
echo "SEEDS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${packages}/scripts
echo "####################################################"
echo "SCRIPTS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${working}/functions
echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i --legacy-peer-deps
npm i -D @types/node@16

cd ${working}
