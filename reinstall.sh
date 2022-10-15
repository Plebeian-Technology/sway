#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

echo ""
echo "Find and destroy all package-lock.json files."
find . -name package-lock.json -type f -delete

echo ""
echo "Find and destroy all node_module directories."
find . -name node_modules -type d -exec rm -rf "{}" +

cd ${packages}/types
echo "####################################################"
echo "TYPES - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i -D @types/node@16

cd ${packages}/constants
echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i -D @types/node@16
pnpm run build

cd ${packages}/utils
echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i -D @types/node@16
pnpm i ../constants
pnpm run build

cd ${packages}/fire
echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i -D @types/node@16
pnpm i ../constants
pnpm i ../utils
pnpm run build

cd ${packages}/webapp
echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i ../constants
pnpm i ../utils
pnpm i ../fire
pnpm i -D @types/node@16

cd ${packages}/seeds
echo "####################################################"
echo "SEEDS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i ../constants
pnpm i ../utils
pnpm i ../fire
pnpm i -D @types/node@16

cd ${packages}/scripts
echo "####################################################"
echo "SCRIPTS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i ../constants
pnpm i ../utils
pnpm i ../fire
pnpm i -D @types/node@16

cd ${working}/functions
echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
# npx npm-check-updates -u --filter="@typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
pnpm i
pnpm i -D @types/node@16

cd ${working}

pnpm i prettier