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
npm i -D @types/node@16

cd ${packages}/constants
echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i -D @types/node@16
npm run build

cd ${packages}/utils
echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i -D @types/node@16
npm i ../constants
npm run build

cd ${packages}/fire
echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i -D @types/node@16
npm i ../constants
npm i ../utils
npm run build

cd ${packages}/webapp
echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i ../constants
npm i ../utils
npm i ../fire
npm i -D @types/node@16

cd ${packages}/seeds
echo "####################################################"
echo "SEEDS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i ../constants
npm i ../utils
npm i ../fire
npm i -D @types/node@16

cd ${packages}/scripts
echo "####################################################"
echo "SCRIPTS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i ../constants
npm i ../utils
npm i ../fire
npm i -D @types/node@16

cd ${working}/functions
echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
npm i
npm i -D @types/node@16

cd ${working}

npm i prettier