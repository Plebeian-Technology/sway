#!/usr/bin/env bash

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

set -eu

./ci-install.sh

# if [ -z ${TWITTER_TOKEN} ]; then
#     firebase functions config set:
# fi

####################################################
# DEV FUNCTIONS
####################################################
firebase use dev

npm run deploy:functions

####################################################
# PROD FUNCTIONS + HOSTING
####################################################

firebase use prod

npm run deploy:functions

./deploy-hosting.sh
