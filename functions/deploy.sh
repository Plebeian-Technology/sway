#!/usr/bin/env bash

ENV=${1:-"development"}
FUNC=${2:-""}
working=$(pwd)
parent="${working}/../.."

echo "Deploying functions to environment - ${ENV}"
echo "Specific function to deploy? ${FUNC}"

firebase use ${ENV}

yarn

if [ "$FUNC" != "" ]; then
    echo "deploying specific function - ${FUNC}"
    GOOGLE_APPLICATION_CREDENTIALS=${parent}/keys/sway-${ENV}.json \
    firebase deploy --only functions:$FUNC
else
    echo "deploying all functions"
    GOOGLE_APPLICATION_CREDENTIALS=${parent}/keys/sway-${ENV}.json \
    firebase deploy --only functions
fi
