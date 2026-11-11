---
mode: explanation
summary: "Explains why ApiKey::MissingHmacSecretError is a plain StandardError and why hmac_secret_key must never gain a .strip without re-verifying safety."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# ApiKey HMAC secret handling

`ApiKey` signs and verifies API tokens with `API_KEY_HMAC_SECRET_KEY` via
HMAC-SHA512. Two design decisions around that secret are not obvious from the
code alone.

## Why MissingHmacSecretError is a plain StandardError

`raise ActiveRecord::RecordInvalid, "<message>"` does not actually raise
`RecordInvalid`: `RecordInvalid.exception` calls `#errors` on the String it
was handed, so it dies with `NoMethodError` and the message is lost.

Borrowing an ActiveRecord class was also the wrong shape. A missing
credential is a config mistake, not an invalid record, and
`.authenticate_by_token` catches `RecordNotFound` to mean "unknown token" — a
misconfigured deployment must not look like a bad credential. `ApiKey::MissingHmacSecretError`
is declared beside the only code that raises it, the same pattern as
`SmsDeliveryJob::DeliveryError`.

## The HMAC secret's newline trap

`API_KEY_HMAC_SECRET_KEY` is the dangerous secret among Sway's credentials. A
stray newline does not cause a 401; it silently changes every digest
computed and checked, so both sides keep agreeing until the value is next
read without that newline — a redeploy, a rotation — and every issued key
stops verifying at once.

That risk is why `ApiKey.hmac_secret_key` does not `.strip` the value before
using it. Adding `.strip` could invalidate every stored digest that depends
on the exact (possibly newline-carrying) bytes.

Once real digests exist, trimming the secret would be a silent mass
invalidation requiring every key holder to be re-issued a token.

## Why hmac_secret_key is a method, not a constant

`ApiKey.hmac_secret_key` used to be a constant. It is a method now so the
value is read fresh on every call — a test can reach the
environment-reading branch, rather than getting whatever value happened to
be memoized when the class first loaded.

## Why the token-blank check raises RecordInvalid, but the missing-secret check doesn't

`#generate_token_hmac_digest` raises two different exceptions for two
different failures. `token` (the raw, un-hashed value) lives only in
memory — `attr_accessor`, never a column — so it can carry no column-level
validation; the blank check has to live in this callback instead, adding a
real error and raising a genuine `ActiveRecord::RecordInvalid` built from
the record, because a blank token really does make the record invalid and
callers already rescue that exception. A missing HMAC secret is a
different kind of failure — a misconfigured deployment, not a bad
record — so it raises `MissingHmacSecretError` instead (see above).

## What ApiKey#to_builder sends, and what it withholds

`ApiKey#to_builder` sends only what the API Keys page shows: `id`, `name`,
`created_at`, `last_used_on_utc`. It never sends `token_digest` (the signed
secret itself) or `bearer_id`/`bearer_type` — the session already knows
which user is signed in, so the payload has no reason to restate it.

The frontend type mirror (`app/frontend/index.d.ts`) puts it this way:
matches what `ApiKey#to_builder` sends. `token_digest` never goes out,
because it is the signing secret; the `bearer_*` values come from the
auth layer instead. The plain `token` for a just-created key arrives
separately in `flash[:new_api_key_token]`, not on this object.

## Why UserDevice#revoke! expires keys in the same transaction

`UserDevice#revoke!` marks the device revoked (`revoked_at`) and expires
every `ApiKey` that belongs to it in one transaction, so the two writes
cannot come apart — a crash between them could otherwise leave a device
marked revoked while its keys stayed live, or vice versa. After a "sign
out device" action, anyone still holding one of that device's keys is
locked out immediately rather than eventually.

## Why the blank-token spec asserts the exact error class and message

The spec for a blank `token` used to assert only `raise_error(StandardError)`,
with a comment explaining that the raise itself dies with `NoMethodError`
("undefined method 'errors' for an instance of String"), because
`ActiveRecord::RecordInvalid#initialize` calls `record.errors` on whatever it
is given — the same defect described above under "Why MissingHmacSecretError
is a plain StandardError". Asserting the specific class and message turns
that defect into a failing test instead of a documented curiosity: an
operator reading the log must be able to tell "this key is unknown" from
"this deployment cannot create keys at all".

## Why an ApiKey's active? check covers user_device revocation

`ApiKey#active?` is true only when the key has no `expires_at` or that
time is still in the future, AND it is linked to no `user_device` or that
device has not been revoked. Mobile sessions always carry both an
`expires_at` and a `user_device` link, so revoking the device from another
screen, or simply letting the token age out, ends that mobile session at
its very next request — without a separate step to invalidate the token
itself.
