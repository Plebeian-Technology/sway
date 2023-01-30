#!/usr/bin/env zsh

working=$(pwd)
packages=${working}/packages

UPDATE={$1:-""}
INSTALL={$2}

set -eu

echo "####################################################"
echo "TYPES - $PWD"
echo "####################################################"
npx npm-check-updates --cwd ${packages}/types --packageFile ${packages}/types/package.json ${UPDATE}
if [[ -v "$INSTALL" ]]; then
    echo "Installing TYPES - $PWD"
    npm i
fi

echo "####################################################"
echo "CONSTANTS - $PWD"
echo "####################################################"
npx npm-check-updates --cwd ${packages}/constants --packageFile ${packages}/constants/package.json ${UPDATE}
if [[ -v "$INSTALL" ]]; then
    echo "Installing CONSTANTS - $PWD"
    npm i
fi

echo "####################################################"
echo "UTILS - $PWD"
echo "####################################################"
npx npm-check-updates --cwd ${packages}/utils --packageFile ${packages}/utils/package.json ${UPDATE}
if [[ -v "$INSTALL" ]]; then
    echo "Installing UTILS - $PWD"
    npm i
fi

echo "####################################################"
echo "FIRE - $PWD"
echo "####################################################"
npx npm-check-updates --cwd ${packages}/fire --packageFile ${packages}/fire/package.json ${UPDATE}
if [[ -v "$INSTALL" ]]; then
    echo "Installing FIRE - $PWD"
    npm i
fi

echo "####################################################"
echo "WEBAPP - $PWD"
echo "####################################################"
npx npm-check-updates --cwd ${packages}/webapp --packageFile ${packages}/webapp/package.json ${UPDATE}
if [[ -v "$INSTALL" ]]; then
    echo "Installing WEBAPP - $PWD"
    npm i
fi

echo "####################################################"
echo "FUNCTIONS - $PWD"
echo "####################################################"
npx npm-check-updates --cwd ${working}/functions --packageFile ${working}/functions/package.json ${UPDATE}
if [[ -v "$INSTALL" ]]; then
    echo "Installing FUNCTIONS - $PWD"
    npm i
fi