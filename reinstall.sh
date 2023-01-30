#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

echo ""
echo "Find and destroy all package-lock.json files."
find . -name package-lock.json -type f -delete

echo ""
echo "Find and destroy all node_module directories."
find . -name node_modules -type d -exec rm -rf "{}" +

echo "auto-install-peers=true" > .npmrc

cd ${packages}/types
echo "####################################################"
echo "TYPES - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i

cd ${packages}/constants
echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm run build

cd ${packages}/utils
echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i ${packages}/constants
npm run build

cd ${packages}/fire
echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i ${packages}/constants ${packages}/utils
npm run build

cd ${packages}/webapp
echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i ${packages}/constants ${packages}/utils ${packages}/fire

cd ${packages}/seeds
echo "####################################################"
echo "SEEDS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i ${packages}/constants ${packages}/utils ${packages}/fire

cd ${packages}/scripts
echo "####################################################"
echo "SCRIPTS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i ${packages}/constants ${packages}/utils ${packages}/fire

cd ${working}/functions
echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i

cd ${working}

npm i prettier