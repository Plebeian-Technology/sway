#!/usr/bin/env bash

unset GOOGLE_APPLICATION_CREDENTIALS

firebase use dev

npm run build

node -r dotenv/config dist/index.js dotenv_config_path=./.env.development congress