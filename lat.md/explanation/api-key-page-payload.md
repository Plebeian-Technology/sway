---
lat:
  mode: explanation
---

# API key page payload

The API key list needs management metadata, not the credential that authenticates requests.

## Listing a key never returns its digest or bearer identity

[[app/models/api_key.rb#ApiKey#to_builder]] sends the API key page its id, name, creation time, and last-use date. The digest and bearer association stay server-side; only a newly created plaintext token travels through the one-time flash covered by [[identity-and-access#The one response whose body carries a secret is never stored]].

## Why ApiKeys.tsx tracks dismissed tokens in state and transforms update payloads

[[app/frontend/pages/ApiKeys.tsx]] derives dialog visibility from `dismissedToken` state and builds rename payloads through `updateForm.transform` at request time.

Comparing `flash?.new_api_key_token` against `dismissedToken` during render shows the one-time token modal whenever a new token arrives without synchronizing state inside an effect. For key renames, `updateForm.transform` reads `newName` when `put` builds the request; calling `setData` immediately before `put` would send the previous render's state.
