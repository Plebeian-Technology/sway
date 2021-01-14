#!/usr/bin/env bash

ENV=${1:-"dev"}
working=$(pwd)

echo "Emulating ${ENV} environment"

firebase use ${ENV}

unset GOOGLE_APPLICATION_CREDENTIALS

cd packages/functions
# run the below from inside the functions directory
# https://firebase.google.com/docs/functions/local-emulator#set_up_functions_configuration_optional
echo "getting sway-dev config to .runtimeconfig.json file"
firebase functions:config:get > ./lib/.runtimeconfig.json
cd ${working}

firebase emulators:start