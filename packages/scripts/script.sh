#!/usr/bin/env bash

ENV=${1}
SCRIPT=${2}
WORKING=$(pwd)
PARENT="${WORKING}/../.."

echo "Running script ${SCRIPT}"
echo "Script args ${@:3}"

export GOOGLE_APPLICATION_CREDENTIALS="${PARENT}/keys/sway-$ENV.json"

firebase use ${ENV}

npm run build

# node -r dotenv/config "${PWD}/${SCRIPT}" dotenv_config_path=$PWD/.env.${ENV} ${@:3}
node -r dotenv/config dist/index.js dotenv_config_path=./.env.${ENV} ${SCRIPT} ${@:3}