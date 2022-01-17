#!/usr/bin/env bash

ENVIRONMENT=${2:-""}

set -eu

if [[ "$ENVIRONMENT" = "dev" ]]; then
    echo ""
    echo ""
    echo ""
    echo "############################################################"
    echo ""
    echo "DEPLOYING FUNCTION - ${1} - TO ONLY DEV"
    echo ""
    echo "############################################################"
    echo ""
    echo ""
    echo ""

    firebase use dev
    npm -C ./functions run deploy:function -- functions:${1}
elif [[ "$ENVIRONMENT" = "prod" ]]; then
    echo ""
    echo ""
    echo ""
    echo "############################################################"
    echo ""
    echo "DEPLOYING FUNCTION - ${1} - TO ONLY PROD"
    echo ""
    echo "############################################################"
    echo ""
    echo ""
    echo ""

    firebase use prod
    npm -C ./functions run deploy:function -- functions:${1}
else
    echo ""
    echo ""
    echo ""
    echo "############################################################"
    echo ""
    echo "DEPLOYING FUNCTION - ${1} - FIRST TO DEV"
    echo ""
    echo "############################################################"
    echo ""
    echo ""
    echo ""
    firebase use dev
    npm -C ./functions run deploy:function -- functions:${1}

    echo ""
    echo ""
    echo ""
    echo "############################################################"
    echo ""
    echo "DEPLOYING FUNCTION - ${1} - LAST TO PROD"
    echo ""
    echo "############################################################"
    echo ""
    echo ""
    echo ""

    firebase use prod
    npm -C ./functions run deploy:function -- functions:${1}
fi
