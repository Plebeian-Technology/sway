#!/usr/bin/env zsh

source ~/.zshrc

working=$(pwd)
packages=${working}/packages

nvm install 14
nvm use 14

echo "####################################################"
echo "TYPES"
echo "####################################################"
cd ${packages}/types
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps

echo "####################################################"
echo "CONSTANTS"
echo "####################################################"
cd ${packages}/constants
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm run build

echo "####################################################"
echo "UTILS"
echo "####################################################"
cd ${packages}/utils
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm run build

echo "####################################################"
echo "FIRE"
echo "####################################################"
cd ${packages}/fire
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps
npm run build

echo "####################################################"
echo "WEBAPP"
echo "####################################################"
cd ${packages}/webapp
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps

echo "####################################################"
echo "SEEDS"
echo "####################################################"
cd ${packages}/seeds
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps

echo "####################################################"
echo "SCRIPTS"
echo "####################################################"
cd ${packages}/scripts
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps

echo "####################################################"
echo "FUNCTIONS"
echo "####################################################"
cd ${packages}/functions
npx npm-check-updates -u --filter="@types/node @typescript-eslint/eslint-plugin @typescript-eslint/parser eslint typescript"
rm -rf node_modules package-lock.json
npm i --legacy-peer-deps

cd ${working}
