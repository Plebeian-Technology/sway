#!/usr/bin/env zsh

curl -X GET https://api.propublica.org/congress/v1/house/votes/2023/01.json -H "X-API-Key: ${PROPUBLICA_API_KEY}" | jq .
# curl -X GET https://api.propublica.org/congress/v1/118/house/sessions/1/votes/20.json -H "X-API-Key: ${PROPUBLICA_API_KEY}" | jq .