#!/usr/bin/env bash

ENV=${1:-"development"}
LOCALE=${2}
working=$(pwd)
parent="${working}/../.."

if [ "$LOCALE" = "prepare" ]; then
    unset GOOGLE_APPLICATION_CREDENTIALS
    export GCLOUD_PROJECT="sway-dev-3187f"
    export FIREBASE_AUTH_EMULATOR_HOST="localhost:9099"
    export FIRESTORE_EMULATOR_HOST="localhost:8080"

    NODE_ENV=${ENV} npm run build
    cp -r locales dist/locales

    export $(cat ./.env.development | xargs) && NODE_ENV=${ENV} node dist/seed.js ${LOCALE}

    mkdir -p src/data/united_states
    cp -r dist/src/data/united_states/congress src/data/united_states/
    npx prettier --write 'src/data/united_states/congress/**/*.ts'
elif [ "$LOCALE" = "congress" ]; then
    echo "setting firebase environment"
    firebase use ${ENV}

    echo "building seeds"
    NODE_ENV=${ENV} npm run build
    cp -r locales dist/locales

    echo "seeding"
    echo "${parent}/keys/sway-$ENV.json"
    export NODE_ENV=${ENV}
    export GOOGLE_APPLICATION_CREDENTIALS="${parent}/keys/sway-$ENV.json"

    # echo "Seeding Congress - alabama-congress-united_states"
    # node dist/seed.js alabama-congress-united_states
    # echo "Seeding Congress - idaho-congress-united_states"
    # node dist/seed.js idaho-congress-united_states
    # echo "Seeding Congress - minnesota-congress-united_states"
    # node dist/seed.js minnesota-congress-united_states
    # echo "Seeding Congress - north_dakota-congress-united_states"
    # node dist/seed.js north_dakota-congress-united_states
    # echo "Seeding Congress - texas-congress-united_states"
    # node dist/seed.js texas-congress-united_states
    # echo "Seeding Congress - alaska-congress-united_states"
    # node dist/seed.js alaska-congress-united_states
    # echo "Seeding Congress - illinois-congress-united_states"
    # node dist/seed.js illinois-congress-united_states
    # echo "Seeding Congress - mississippi-congress-united_states"
    # node dist/seed.js mississippi-congress-united_states
    # echo "Seeding Congress - ohio-congress-united_states"
    # node dist/seed.js ohio-congress-united_states
    # echo "Seeding Congress - utah-congress-united_states"
    # node dist/seed.js utah-congress-united_states
    # echo "Seeding Congress - arizona-congress-united_states"
    # node dist/seed.js arizona-congress-united_states
    # echo "Seeding Congress - indiana-congress-united_states"
    # node dist/seed.js indiana-congress-united_states
    # echo "Seeding Congress - missouri-congress-united_states"
    # node dist/seed.js missouri-congress-united_states
    # echo "Seeding Congress - oklahoma-congress-united_states"
    # node dist/seed.js oklahoma-congress-united_states
    # echo "Seeding Congress - vermont-congress-united_states"
    # node dist/seed.js vermont-congress-united_states
    # echo "Seeding Congress - arkansas-congress-united_states"
    # node dist/seed.js arkansas-congress-united_states
    # echo "Seeding Congress - iowa-congress-united_states"
    # node dist/seed.js iowa-congress-united_states
    # echo "Seeding Congress - montana-congress-united_states"
    # node dist/seed.js montana-congress-united_states
    # echo "Seeding Congress - oregon-congress-united_states"
    # node dist/seed.js oregon-congress-united_states
    # echo "Seeding Congress - virginia-congress-united_states"
    # node dist/seed.js virginia-congress-united_states
    # echo "Seeding Congress - california-congress-united_states"
    # node dist/seed.js california-congress-united_states
    # echo "Seeding Congress - kansas-congress-united_states"
    # node dist/seed.js kansas-congress-united_states
    # echo "Seeding Congress - nebraska-congress-united_states"
    # node dist/seed.js nebraska-congress-united_states
    # echo "Seeding Congress - pennsylvania-congress-united_states"
    # node dist/seed.js pennsylvania-congress-united_states
    # echo "Seeding Congress - washington-congress-united_states"
    # node dist/seed.js washington-congress-united_states
    # echo "Seeding Congress - colorado-congress-united_states"
    # node dist/seed.js colorado-congress-united_states
    # echo "Seeding Congress - kentucky-congress-united_states"
    # node dist/seed.js kentucky-congress-united_states
    # echo "Seeding Congress - nevada-congress-united_states"
    # node dist/seed.js nevada-congress-united_states
    # echo "Seeding Congress - west_virginia-congress-united_states"
    # node dist/seed.js west_virginia-congress-united_states
    # echo "Seeding Congress - connecticut-congress-united_states"
    # node dist/seed.js connecticut-congress-united_states
    # echo "Seeding Congress - louisiana-congress-united_states"
    # node dist/seed.js louisiana-congress-united_states
    # echo "Seeding Congress - new_hampshire-congress-united_states"
    # node dist/seed.js new_hampshire-congress-united_states
    # echo "Seeding Congress - wisconsin-congress-united_states"
    # node dist/seed.js wisconsin-congress-united_states
    # echo "Seeding Congress - delaware-congress-united_states"
    # node dist/seed.js delaware-congress-united_states
    # echo "Seeding Congress - maine-congress-united_states"
    # node dist/seed.js maine-congress-united_states
    # echo "Seeding Congress - new_jersey-congress-united_states"
    # node dist/seed.js new_jersey-congress-united_states
    # echo "Seeding Congress - rhode_island-congress-united_states"
    # node dist/seed.js rhode_island-congress-united_states
    # echo "Seeding Congress - wyoming-congress-united_states"
    # node dist/seed.js wyoming-congress-united_states
    # echo "Seeding Congress - florida-congress-united_states"
    # node dist/seed.js florida-congress-united_states
    echo "Seeding Congress - maryland-congress-united_states"
    node dist/seed.js maryland-congress-united_states
    # echo "Seeding Congress - new_mexico-congress-united_states"
    # node dist/seed.js new_mexico-congress-united_states
    # echo "Seeding Congress - south_carolina-congress-united_states"
    # node dist/seed.js south_carolina-congress-united_states
    # echo "Seeding Congress - georgia-congress-united_states"
    # node dist/seed.js georgia-congress-united_states
    # echo "Seeding Congress - massachusetts-congress-united_states"
    # node dist/seed.js massachusetts-congress-united_states
    # echo "Seeding Congress - new_york-congress-united_states"
    # node dist/seed.js new_york-congress-united_states
    # echo "Seeding Congress - south_dakota-congress-united_states"
    # node dist/seed.js south_dakota-congress-united_states
    # echo "Seeding Congress - hawaii-congress-united_states"
    # node dist/seed.js hawaii-congress-united_states
    # echo "Seeding Congress - michigan-congress-united_states"
    # node dist/seed.js michigan-congress-united_states
    # echo "Seeding Congress - north_carolina-congress-united_states"
    # node dist/seed.js north_carolina-congress-united_states
    # echo "Seeding Congress - tennessee-congress-united_states"
    # node dist/seed.js tennessee-congress-united_states

elif [ "$ENV" = "emulate" ]; then
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
    node dist/seed.js ${LOCALE}
fi