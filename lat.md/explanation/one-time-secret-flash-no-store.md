---
lat:
  mode: explanation
---

# Why a one-time-secret flash forces Cache-Control: no-store

`ApplicationController::ONE_TIME_SECRET_FLASH_KEYS` (currently just `new_api_key_token`) lists flash keys whose value is a secret the reader is shown exactly once and can never retrieve again.

The session cookie carrying them is encrypted, but the rendered page props are not: the value reaches the browser in plain text inside the rendered page object.

Rails answers a rendered page with `max-age=0, private, must-revalidate` by default, which still permits the browser to keep a copy on disk and revalidate it later. That is the wrong trade when the body carries a secret in plain text, so `forbid_storing_a_one_time_secret` marks any response carrying one of these flash keys `no-store`, which forbids the copy outright.

The flash is swept after one round trip, so exactly one response per created key is ever affected. The check lives in `ApplicationController` rather than in `ApiKeysController` specifically because the flash is shared onto every page — a reader who never follows the post-creation redirect carries the secret onto whatever they load next, where nothing displays it and nothing would have marked that later response `no-store` otherwise.

## Why new_api_key_token reaches the page at all

`ApplicationController`'s `inertia_share flash: -> { flash.to_hash }` passes the WHOLE flash hash along, rather than Inertia's default of a fixed set of flash keys.

That is why the custom `:new_api_key_token` key reaches `ApiKeys.tsx` with no extra configuration — it would not survive a switch to Inertia's default flash sharing. `ApiKeys.tsx` reads that key to offer a "copy to clipboard" button right after a key is made.

The token is genuinely shown only once, at creation: there is no other screen that displays a stored key's raw value. Miss the one-time flash and the only way back is to delete the key and make a new one.
