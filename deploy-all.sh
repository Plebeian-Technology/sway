#!/usr/bin/env bash

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

cd ${WORKING}/packages/functions
npm i
cd ${WORKING}

firebase use dev

# if [ -z ${TWITTER_TOKEN} ]; then
#     firebase functions config set:
# fi

npm run deploy:functions

firebase use prod

npm run deploy:functions

npm run deploy:hosting