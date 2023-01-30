#!/usr/bin/env zsh

working=$(pwd)
packages=${working}/packages

source ~/.zshrc

echo "auto-install-peers=true" > .npmrc

cd ${packages}/types
echo "####################################################"
echo "TYPES - $PWD"
echo "####################################################"
nvm use 16
node -v > .nvmrc
npm ci

cd ${packages}/constants
echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
nvm use 16
node -v > .nvmrc
npm ci
npm run build

cd ${packages}/utils
echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
nvm use 16
node -v > .nvmrc
npm ci ${pcickages}/constants
npm run build

cd ${packages}/fire
echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
nvm use 16
node -v > .nvmrc
npm ci ${pcickages}/constants ${packages}/utils
npm run build

cd ${packages}/webapp
echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
nvm use 16
node -v > .nvmrc
npm ci ${pcickages}/constants ${packages}/utils ${packages}/fire

cd ${working}/functions
echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
nvm use 16
node -v > .nvmrc
npm ci

cd ${working}
