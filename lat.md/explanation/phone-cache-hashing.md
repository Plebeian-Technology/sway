---
lat:
  mode: explanation
---
# Phone cache hashing

Rate-limit buckets and the `SmsVerificationToken` cache entry used to hold a phone number in plain text.

`PhoneCacheKey` (`app/lib/phone_cache_key.rb`) replaces the number with a keyed HMAC-SHA512 digest before either enters the cache, so the same number still buckets together but nobody reading the cache table can recover it.

## A separate secret from ApiKey's

`PhoneCacheKey` reads `PHONE_CACHE_HMAC_SECRET_KEY` through `EnvSecret`, not `ApiKey`'s `API_KEY_HMAC_SECRET_KEY`.

The two secrets protect different things — a phone number versus a mobile bearer token — so a leak of one must not compromise the other. Sharing a secret across purposes, or deriving one from the other, would tie their blast radii together for no benefit; a fresh `openssl rand -hex 32` costs nothing.

## Normalize before hashing, still

Every spelling of one number has to land in the same bucket, which only holds if `normalize_phone` runs before the value is hashed.

`"+14105551234"`, `"4105551234"` and `"1-410-555-1234"` are the same number under `normalize_phone`. `PhoneCacheKey.digest` normalizes internally, so a caller that already normalized upstream (a no-op the second time) and one that never did both get the same answer.

## The anonymous bucket

A blank or unparseable phone digests to the fixed string `"anonymous"` rather than raising or hashing garbage.

This is unchanged from the pre-hashing `.presence || "anonymous"` fallback the four rate-limit `by:` lambdas used before this module existed.
