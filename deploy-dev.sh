#!/usr/bin/env bash

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

set -eu

cd ${WORKING}/functions
pnpm i
cd ${WORKING}

firebase use dev

pnpm run deploy:functions

pnpm -C ./packages/webapp run build

firebase deploy --only hosting