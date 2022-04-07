#!/usr/bin/env bash

working=$(pwd)

echo "emulate.sh - setting firebase env as 'dev'"
firebase use dev

echo "emulate.sh - unset GOOGLE_APPLICATION_CREDENTIALS env var if set"
unset GOOGLE_APPLICATION_CREDENTIALS

echo "emulate.sh - build functions"
npm -C functions run build

echo "emulate.sh - export GCLOUD_PROJECT, FIRESTORE_EMULATOR_HOST, FIREBASE_AUTH_EMULATOR_HOST and FIREBASE_STORAGE_EMULATOR_HOST"
export GCLOUD_PROJECT=sway-dev-3187f
export FIRESTORE_EMULATOR_HOST=localhost:8080
export FIREBASE_AUTH_EMULATOR_HOST=localhost:9099
export FIREBASE_STORAGE_EMULATOR_HOST=localhost:9199

echo "emulate.sh - start emulator"
firebase emulators:start