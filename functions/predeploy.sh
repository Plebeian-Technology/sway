#!/usr/bin/env bash

echo ""
echo "Working directory is:"
echo $PWD
echo ""

npm i ../types

mkdir -p functions/src
rsync -avz ./index.d.ts functions/.
rsync -avz ./src/constants functions/src/
rsync -avz ./src/utils functions/src/
rsync -avz ./src/fire functions/src/

rm -rf ./functions/dist
npm -C ./functions run build
