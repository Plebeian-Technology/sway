#!/usr/bin/env zsh

source ~/.zshrc

TWITTER_TOKEN=${1-""}
WORKING=$(pwd)

cd ${WORKING}/packages/functions
nvm use 14
npm i -g firebase-tools
npm i
cd ${WORKING}


firebase use dev

# if [ -z ${TWITTER_TOKEN} ]; then
#     firebase functions config set:
# fi

npm run deploy:functions

firebase use prod

npm run deploy:functions

nvm use 16

./deploy-hosting.sh