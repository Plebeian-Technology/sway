#!/usr/bin/env bash

firebase use dev

npm run deploy:functions

firebase use prod

npm run deploy:functions

npm run deploy:hosting