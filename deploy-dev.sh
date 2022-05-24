#!/usr/bin/env bash

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

set -eu

cd ${WORKING}/functions
npm i
cd ${WORKING}

firebase use dev

npm run deploy:functions

npm -C ./packages/webapp run build

firebase deploy --only hosting