---
lat:
  mode: explanation
---
# Multiline credentials over Kamal

Kamal's env file cannot carry a value with embedded newlines intact, so the two multiline push credentials travel as Base64 text instead of raw PEM or JSON.

## Why multiline credentials travel as Base64

Kamal escapes an env value with Ruby's `String#dump` before writing it to Docker's env file, and Docker reads that file literally, with no unescaping step of its own.

`Kamal::EnvFile#escape_docker_env_file_value` (kamal 2.12.0) runs every ASCII
value through `dump`, then strips the outer quotes and unescapes `\"` and
`\#` back to literal characters — nothing else. A newline inside a value
survives that round trip as the two characters backslash and `n`, and nothing
downstream turns that pair back into an actual line break.

A PEM private key is built from newlines, so it arrives at the container as

    APNS_AUTH_KEY_P8=-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGB\n-----END PRIVATE KEY-----\n

which OpenSSL rejects — that text is not a key. A Firebase service-account
JSON document fares worse: its `private_key` field already holds `\n`
escapes as part of the JSON encoding, and `dump` doubles each of those to
`\\n`. Once Rails calls `JSON.parse` on the arriving string, googleauth is
handed a key containing literal backslash characters rather than line breaks,
and signing fails.

Both failures are silent in production, the same way an absent credential is
silent: `ApnsClient.deliver` and `FcmClient.deliver` return early when their
configuration is missing and log nothing, so a broken push stack and a dark
one look identical from outside.

The contract that avoids this: the two multiline values are stored, and
travel through Kamal, as strict Base64, not as the raw PEM or JSON text.
`EnvSecret.read_base64` (`app/lib/env_secret.rb`) is the single decode point —
`config/initializers/apns.rb` reads `APNS_AUTH_KEY_P8` through it and
`config/initializers/fcm.rb` reads `FCM_SERVICE_ACCOUNT_JSON` through it. A
value that fails strict Base64 decoding comes back as `nil` with an error
logged naming the variable, rather than raising. Raising would let a single
malformed push credential take the whole site down at boot; the cost of not
raising is that push to phones stays dark on that credential, which is the
same dark state an absent credential produces — the log line is what tells
the two apart.

The remaining push values — `APNS_KEY_ID`, `APPLE_TEAM_ID`, `APPLE_BUNDLE_ID`,
`APNS_ENV` — are single-line, so none of this applies to them: they cross
Kamal's env file intact and are trimmed either inline, as
[[pre-autoload-credential-trimming]] documents, or by the settings string
caster for the two `APPLE_*` names.
