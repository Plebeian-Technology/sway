#!/usr/bin/env bash

ENV=${1:-"development"}
OPERATION=${2-"seed"}
SELECTED_LOCALE=${3}
CONGRESS_LOCALE="congress-congress-united_states"
WORKING=$(pwd)
PARENT="${WORKING}/../.."

echo "SEED ENVIRONMENT - ${ENV}"
echo "SEED SELECTED LOCALE - ${SELECTED_LOCALE}"

export NODE_ENV=${ENV}
export GOOGLE_APPLICATION_CREDENTIALS="${PARENT}/keys/sway-$ENV.json"

function seed() {

    locale=${1}
    echo "SEED FUNCTION locale - ${locale}"
    echo "SEED FUNCTION ENV - ${ENV}"
    echo "SEED FUNCTION OPERATION - ${OPERATION}"
    echo "SEED FUNCTION SELECTED_LOCALE - ${SELECTED_LOCALE}"
    echo "SEED FUNCTION EMULATION? - ${REACT_APP_EMULATE}"

    if [ "$REACT_APP_EMULATE" = "1" ]; then
        echo "RUNNING SEEDS AGAINST EMULATION ENVIRONMENT"

        GCLOUD_PROJECT="sway-dev-3187f" \
            FIREBASE_AUTH_EMULATOR_HOST="localhost:9099" \
            FIRESTORE_EMULATOR_HOST="localhost:8080" \
            npm run build

        GCLOUD_PROJECT="sway-dev-3187f" \
            FIREBASE_AUTH_EMULATOR_HOST="localhost:9099" \
            FIRESTORE_EMULATOR_HOST="localhost:8080" \
            REACT_APP_EMULATE=1 \
            node dist/seed.js ${OPERATION} ${locale}

    elif [ "$ENV" = "test" ]; then
        export GCLOUD_PROJECT="sway-dev-3187f"
        export FIREBASE_AUTH_EMULATOR_HOST="localhost:9099"
        export FIRESTORE_EMULATOR_HOST="localhost:8080"

        node dist/seed.js ${OPERATION} ${locale}
    else
        echo "Using Key"
        echo "${PARENT}/keys/sway-$ENV.json"

        export $(cat ./.env.${ENV} | xargs)

        if [[ ${SELECTED_LOCALE} = ${CONGRESS_LOCALE} ]]; then
            echo "UPDATE FILES FOR CONGRESS LOCALE"
            mkdir -p src/data/united_states
            cp -r dist/src/data/united_states/congress src/data/united_states/

            npx prettier --write 'src/data/united_states/congress/**/*.ts'
            find src/data/ -type f -name "*.js" -delete
            find dist/src/data/ -type f -name "*.ts" -delete
        fi

        node dist/seed.js ${OPERATION} ${locale}
    fi
}

echo "Setting firebase environment"
firebase use ${ENV}

echo "Building seeds"
npm run build

if [[ -z "$SELECTED_LOCALE" ]]; then
    echo "SEEDING ALL LOCALES"
    for locale in $(cat locales.txt); do
        echo "SEEDING LOCALE - ${locale}"
        seed ${locale}
    done
else
    echo "SEEDING SELECTED LOCALE - ${SELECTED_LOCALE}"
    seed ${SELECTED_LOCALE}
fi
