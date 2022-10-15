#!/usr/bin/env bash

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

set -eu

cd ${WORKING}/functions
pnpm i
cd ${WORKING}

firebase use dev

# if [ -z ${TWITTER_TOKEN} ]; then
#     firebase functions config set:
# fi

pnpm run deploy:functions

firebase use prod

pnpm run deploy:functions

./deploy-hosting.sh