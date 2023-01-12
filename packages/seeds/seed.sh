#!/usr/bin/env bash

ENV=${1:-"development"}
OPERATION=${2:-"seed"}
SELECTED_LOCALE=${3:-"baltimore-maryland-united_states"}
CONGRESS_LOCALE="congress-congress-united_states"
WORKING=$(pwd)
PARENT="${WORKING}/../.."

echo "SEED ENVIRONMENT - ${ENV}"
echo "SEED SELECTED LOCALE - ${SELECTED_LOCALE}"

set -eu

export NODE_ENV=${ENV}
export GOOGLE_APPLICATION_CREDENTIALS="${PARENT}/keys/sway-$ENV.json"
export CONGRESS_IMAGE_REPO_URL="https://www.congress.gov/img/member"

function seed() {

    locale=${1}
    echo "SEED FUNCTION locale - ${locale}"
    echo "SEED FUNCTION ENV - ${ENV}"
    echo "SEED FUNCTION OPERATION - ${OPERATION}"
    echo "SEED FUNCTION SELECTED_LOCALE - ${SELECTED_LOCALE}"
    echo "SEED FUNCTION EMULATION? - ${REACT_APP_EMULATE}"

    if [ "$REACT_APP_EMULATE" = "1" ]; then
        echo "RUNNING SEEDS AGAINST EMULATION ENVIRONMENT"

        echo "Using Key"
        echo "${PARENT}/keys/sway-$ENV.json"

        export $(cat ./.env.${ENV} | xargs)

        if [[ "$SELECTED_LOCALE" = "$CONGRESS_LOCALE" ]]; then
            echo "UPDATE FILES FOR CONGRESS LOCALE"
            mkdir -p src/data/united_states
            cp -r dist/src/data/united_states/congress src/data/united_states/

            npx prettier --write 'src/data/united_states/congress/**/*.ts'
            find src/data/ -type f -name "*.js" -delete
            find dist/src/data/ -type f -name "*.ts" -delete
        fi

        export GCLOUD_PROJECT=sway-dev-3187f
        export FIREBASE_AUTH_EMULATOR_HOST=localhost:9099
        export FIRESTORE_EMULATOR_HOST=localhost:8080
        export FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199
        
        echo "seed.sh - emulate - locales - SELECTED_LOCAL - ${SELECTED_LOCALE}"
        node dist/seed.js locales

        echo "seed.sh - emulate - prepare - SELECTED_LOCAL - ${SELECTED_LOCALE}"
        node dist/seed.js prepare ${SELECTED_LOCALE}

        echo "seed.sh - emulate - storage - SELECTED_LOCAL - ${SELECTED_LOCALE}"
        node dist/seed.js storage ${SELECTED_LOCALE} | true

        echo "seed.sh - emulate - seed - SELECTED_LOCAL - ${SELECTED_LOCALE}"
        node dist/seed.js seed ${SELECTED_LOCALE}

        if [[ "$SELECTED_LOCALE" != "$CONGRESS_LOCALE" ]]; then
            echo "seed.sh - emulate - sheets - SELECTED_LOCAL - ${SELECTED_LOCALE}"
            node dist/seed.js sheets ${SELECTED_LOCALE}
        fi

    elif [ "$ENV" = "test" ]; then
        export GCLOUD_PROJECT=sway-dev-3187f
        export FIREBASE_AUTH_EMULATOR_HOST=localhost:9099
        export FIRESTORE_EMULATOR_HOST=localhost:8080
        export FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199

        node dist/seed.js ${OPERATION} ${locale}
    else
        echo "Using Key"
        echo "${PARENT}/keys/sway-$ENV.json"

        export $(cat ./.env.${ENV} | xargs)

        if [[ "$SELECTED_LOCAL" = "$CONGRESS_LOCALE" ]]; then
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
