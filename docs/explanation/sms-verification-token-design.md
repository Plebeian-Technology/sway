---
mode: explanation
summary: "Explains SmsVerificationToken's replay defense (delete-then-check-return-value), why it lives in Rails.cache instead of the database, and why #peek leaves the token unspent."
status: agent-extracted
related: []
---
<!-- vale Vale.Spelling = NO -->

# Why SmsVerificationToken is built the way it is

`SmsVerificationToken` is a single-use proof that someone owns a phone
number.

`POST /api/v1/phone_verification/verify` hands out the token after a
correct SMS code. It is then spent by either `POST /api/v1/sessions`
(logging in by SMS instead of a passkey) or `POST /api/v1/registrations`
(setting up a passkey). The token is tied to one phone number and lives in
`Rails.cache`, not the database. Present the same token twice and the
second attempt returns false, so the controller answers 401
`invalid_sms_token`.

## The replay defense

The attack this guards against is replay — someone grabbing a token and
using it again. The defence is deleting the cache entry the first time
the token is spent, and only letting through the caller whose delete
actually removed it. That way two requests racing with the same token
cannot both win.

`Rails.cache.delete` is the check: every cache backend Sway uses returns
false to the loser of that race — `MemoryStore` is internally locked,
`FileStore` relies on `File.delete` — so if two requests present the same
token at the same moment, only one can slip through the gap between
reading and deleting.

`#consume!` spends the token by looking at it even when the phone number
does not match. Burning it either way stops someone from trying one token
against phone number after phone number.

## Why it lives in Rails.cache, not the database

`Rails.cache` is not part of database transactions, so a rolled-back
transaction cannot bring a spent token back. That is on purpose: once a
token has been seen and accepted, it is gone. If whatever the caller did
next fails, the user simply asks for a new SMS code.

## Why #peek exists alongside #consume!

`#peek` looks at a token without spending it, returning the stored
`{ phone:, issued_at: }` hash for a token that is still alive, or nil if
the token is blank, unknown, or expired. Unlike `#consume!` it leaves the
cache entry in place, so a later `#consume!` can still enforce single use.
Code that needs to check a token before it is ready to spend it — such as
`registrations#create` confirming the phone number matches before the
passkey setup begins — calls this instead of reading `Rails.cache`
itself, so the cache-key layout stays this class's business.
