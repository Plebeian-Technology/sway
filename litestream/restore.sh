#!/usr/bin/env zsh

echo ""
echo "###################################################################################################"
echo ""
echo "restore.sh - Restoring the production db from Digial Ocean via Litestream to storage/production.db"
echo ""

litestream restore -config litestream/config/restore.yml storage/production.db

echo ""
echo "restore.sh - Finished restoring the production db from Digial Ocean via Litestream to stroage/production.db"
echo ""
echo "###################################################################################################"
echo ""