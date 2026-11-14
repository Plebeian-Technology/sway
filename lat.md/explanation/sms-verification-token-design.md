---
lat:
  mode: explanation
---

# Why SmsVerificationToken is built the way it is

`SmsVerificationToken` is a single-use proof that someone owns a phone number.

`POST /api/v1/phone_verification/verify` hands out the token after a correct SMS code. It is then spent by [[app/controllers/api/v1/registrations_controller.rb#RegistrationsController#callback]] or [[app/controllers/api/v1/passkeys_controller.rb#PasskeysController#callback]] when enrolling a passkey. The token is tied to one phone number and lives in `Rails.cache`, not the database. A replayed token is caught before any write, by a [[app/services/sms_verification_token.rb#SmsVerificationToken#peek]] check that precedes the already-registered check, so a second callback answers 401 `invalid_sms_token` rather than reporting the account the first one created. [[app/services/sms_verification_token.rb#SmsVerificationToken#consume!]] spends the token later, and a `false` return there rolls the transaction back the same way. The registrations callback spends it only once account creation has otherwise succeeded ([[sms-verification-token-design#Why the token is spent last]]); the passkeys callback spends it once the new passkey is known valid, before saving it.

## The replay defense

The attack this guards against is replay — someone grabbing a token and using it again.

The defence is deleting the cache entry the first time the token is spent, and only letting through the caller whose delete actually removed it. That way two requests racing with the same token, or two challenges minted via `#peek` from one token, cannot both complete enrollment.

`Rails.cache.delete` is the check: every cache backend Sway uses returns false to the loser of that race — `MemoryStore` is internally locked, `FileStore` relies on `File.delete` — so if two requests present the same token at the same moment, only one can slip through the gap between reading and deleting.

`#consume!` compares the stored phone digest with [[app/lib/phone_cache_key.rb#PhoneCacheKey#digest]] via `ActiveSupport::SecurityUtils.secure_compare` after deleting the entry, so it spends the token even when the phone number does not match. Burning it either way stops someone from trying one token against phone number after phone number.

## Why it lives in Rails.cache, not the database

`Rails.cache` is not part of database transactions, so a rolled-back transaction cannot bring a spent token back.

That is on purpose: once a token has been seen and accepted, it is gone. A write that fails after the spend leaves the user needing a new SMS code, so where the spend sits in a transaction decides what a failure costs.

## Why the token is spent last

The registrations callback spends the token as the last statement of its transaction, after the user, passkey, notification preferences, device and API key are written.

A failure in any of those writes rolls the database back, and the token is still in `Rails.cache` because nothing has spent it yet. The mobile app keeps the token, so the user retries the passkey step without a second SMS and a second code to type. Spending first would cost the user a new code for a fault on Sway's side.

Single use still holds. SQLite's immediate transactions serialize writers ([[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]), so a second callback for the same token begins only after the first has committed, and its [[app/services/sms_verification_token.rb#SmsVerificationToken#peek]] check finds no token. A `false` return from `#consume!` at the end still rolls back every write and answers 401 `invalid_sms_token`.

## Why peek exists alongside consume!

`#peek` looks at a token without spending it, returning the stored `{ phone:, issued_at: }` hash for a token that is still alive, or nil if the token is blank, unknown, or expired.

Unlike `#consume!` it leaves the cache entry in place, so a later `#consume!` can still enforce single use. Code that needs to check a token before it is ready to spend it — such as `registrations#create` confirming the phone number matches before the passkey setup begins — calls this instead of reading `Rails.cache` itself, so the cache-key layout stays this class's business.
