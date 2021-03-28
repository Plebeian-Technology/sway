#!/usr/bin/env bash

echo ""
echo ""
echo ""
echo "############################################################"
echo ""
echo "DEPLOYING FUNCTION - ${1} - TO DEV"
echo ""
echo "############################################################"
echo ""
echo ""
echo ""

firebase use dev; npm run deploy:function -- functions:${1}

echo ""
echo ""
echo ""
echo "############################################################"
echo ""
echo "DEPLOYING FUNCTION - ${1} - TO PROD AFTER SLEEPING 10"
echo ""
echo "############################################################"
echo ""
echo ""
echo ""
sleep 10
firebase use prod; npm run deploy:function -- functions:${1}