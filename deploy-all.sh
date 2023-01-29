#!/usr/bin/env bash

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

set -eu

./ci-install.sh

firebase use dev

# if [ -z ${TWITTER_TOKEN} ]; then
#     firebase functions config set:
# fi

npm run deploy:functions

# firebase use prod

# npm run deploy:functions

# ./deploy-hosting.sh