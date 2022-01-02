#!/usr/bin/env zsh

KEY=${1}
VALUE=${2}

firebase use dev
firebase functions:config:set ${KEY}=${VALUE}

firebase use prod
firebase functions:config:set ${KEY}=${VALUE}