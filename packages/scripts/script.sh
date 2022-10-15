#!/usr/bin/env bash

SCRIPT_PATH=${1}
ENV=${2:-"development"}
WORKING=$(pwd)
PARENT="${WORKING}/../.."

echo "Running script ${SCRIPT_PATH}"
echo "Script args ${@:3}"

export GOOGLE_APPLICATION_CREDENTIALS="${PARENT}/keys/sway-$ENV.json"

firebase use ${ENV}

pnpm run build

node -r dotenv/config ${SCRIPT_PATH} dotenv_config_path=./.env.${ENV} ${@:3}