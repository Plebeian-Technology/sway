#!/usr/bin/env bash

working=$(pwd)

firebase use dev

unset GOOGLE_APPLICATION_CREDENTIALS

export FIRESTORE_EMULATOR_HOST=localhost:8080
export FIREBASE_STORAGE_EMULATOR_HOST="localhost:9199"
firebase emulators:start