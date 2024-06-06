#!/usr/bin/env zsh

export GOOGLE_APPLICATION_CREDENTIALS="${HOME}/.config/gcloud/application_default_credentials.json"

echo ""
echo "###################################################################################################"
echo ""
echo "replicate.sh - Replicating the production db to Digial Ocean via Litestream"
echo ""

rm -rf litestream/dbs
mkdir -p litestream/dbs
touch litestream/dbs/.keep

gsutil cp gs://sway-sqlite/production.sqlite3 litestream/dbs/production.sqlite3

litestream replicate -exec "sleep 10" -config litestream/config/replicate.yml

rm -rf litestream/dbs
mkdir -p litestream/dbs
touch litestream/dbs/.keep

echo ""
echo "replicate.sh - Finished replicating the production db to Digial Ocean via Litestream"
echo ""
echo "###################################################################################################"
echo ""