#!/usr/bin/env bash

set -eu

firebase use prod

CURRENT_VERSION=$(cat ./packages/webapp/VERSION.txt)
NEXT_VERSION=$(($CURRENT_VERSION + 1))
echo ${NEXT_VERSION} > ./packages/webapp/VERSION.txt

echo "################################################"
echo ""
echo "Current version is - ${CURRENT_VERSION}"
echo "Next version is - ${NEXT_VERSION}"
echo ""
echo "################################################"
echo ""

# Remove last line from file https://stackoverflow.com/a/4881990/6410635
sed -i '' -e '$ d' ./packages/webapp/.env.development
echo "REACT_APP_SWAY_VERSION=${NEXT_VERSION}" >> ./packages/webapp/.env.development

sed -i '' -e '$ d' ./packages/webapp/.env.production
echo "REACT_APP_SWAY_VERSION=${NEXT_VERSION}" >> ./packages/webapp/.env.production

npm -C ./packages/webapp run build

echo ""
echo "################################################"
echo ""
echo "Completed Building Webapp Package."
date
echo ""
echo "################################################"
echo ""

firebase deploy --only hosting

echo ""
echo "################################################"
echo ""
echo "Finished Deployed Webapp to Hosting."
date
echo ""
echo "################################################"
echo ""

echo ""
echo "################################################"
echo ""
echo "Updating Sway Version to ${NEXT_VERSION}."
echo ""
echo "################################################"
echo ""

echo "Update Version Dev"
curl \
    -X POST \
    -H "Content-Type:application/json" \
    https://us-central1-sway-dev-3187f.cloudfunctions.net/updateSwayVersion \
    -d "{\"version\": ${NEXT_VERSION} }" | jq .

echo "Deploy Version Prod"
curl \
    -X POST \
    -H "Content-Type:application/json" \
    https://us-central1-sway-7947e.cloudfunctions.net/updateSwayVersion \
    -d "{\"version\": ${NEXT_VERSION} }" | jq .
