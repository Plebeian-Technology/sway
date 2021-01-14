#!/usr/bin/env bash

ENV=${1:-"development"}
LOCALE=${2}
working=$(pwd)
parent="${working}/../.."

if [ "$ENV" = "emulate" ]; then
    unset GOOGLE_APPLICATION_CREDENTIALS
    firebase use sway-dev

    GCLOUD_PROJECT="sway-dev-3187f" \
    FIREBASE_AUTH_EMULATOR_HOST="localhost:9099" \
    FIRESTORE_EMULATOR_HOST="localhost:8080" \
    NODE_ENV=development npm run build

    cp -r locales dist/locales

    GCLOUD_PROJECT="sway-dev-3187f" \
    FIREBASE_AUTH_EMULATOR_HOST="localhost:9099" \
    FIRESTORE_EMULATOR_HOST="localhost:8080" \
    REACT_APP_EMULATE=1 \
    NODE_ENV=development node dist/seed.js ${LOCALE}
elif [ "$ENV" = "test" ]; then
    unset GOOGLE_APPLICATION_CREDENTIALS
    export GCLOUD_PROJECT="sway-dev-3187f"
    export FIREBASE_AUTH_EMULATOR_HOST="localhost:9099"
    export FIRESTORE_EMULATOR_HOST="localhost:8080"

    NODE_ENV=${ENV} npm run build
    cp -r locales dist/locales

    NODE_ENV=${ENV} node dist/seed.js ${LOCALE}
else
    echo "setting firebase environment"
    firebase use ${ENV}

    echo "building seeds"
    NODE_ENV=${ENV} npm run build
    cp -r locales dist/locales

    echo "seeding"
    echo "${parent}/keys/sway-$ENV.json"
    NODE_ENV=${ENV} \
    GOOGLE_APPLICATION_CREDENTIALS="${parent}/keys/sway-$ENV.json" \
    node -r dotenv/config dist/seed.js ${LOCALE} dotenv_config_path=${parent}/packages/seeds/.env.${ENV}
fi