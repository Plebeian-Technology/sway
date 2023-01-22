#!/usr/bin/env bash

working=$(pwd)
packages=${working}/packages

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

cd ${working}
