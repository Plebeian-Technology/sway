#!/usr/bin/env bash

firebase use prod

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
