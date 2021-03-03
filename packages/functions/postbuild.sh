#!/usr/bin/env bash

echo "rsync-ing geojson files to onInsertUserDistrict function in lib"
mkdir -p lib/geojson
rsync -avz geojson/*.geojson lib/geojson/.

rsync -avz -d types lib/.
rsync -avz -d constants lib/.
rsync -avz -d fire lib/.

# rm -rf types constants fire

echo ""
echo "################################################"
echo ""
echo "Functions post-build script finished."
date
echo ""
echo "################################################"
echo ""