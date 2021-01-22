#!/usr/bin/env bash

ENV=${1:-"development"}
WORKING=$(pwd)
PARENT="${WORKING}/../.."

export GOOGLE_APPLICATION_CREDENTIALS="${PARENT}/keys/sway-$ENV.json"

firebase use ${ENV}

npm run build

node -r dotenv/config dist/index.js dotenv_config_path=./.env.${ENV} congress