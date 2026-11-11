---
mode: explanation
summary: "Why OnDeactivatedPhoneDeleteUserJob batches with compact + each_slice instead of in_groups_of, strips only a real leading +, reports destroy failures to Sentry directly, and treats the deactivation-date Twilio error as PII-free."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `OnDeactivatedPhoneDeleteUserJob` is shaped the way it is

## Why batching uses `compact` + `each_slice`, not `in_groups_of`

`in_groups_of(200)` pads the final group with nils, and
`User.where(phone: [..., nil])` compiles to `phone IN (...) OR phone IS
NULL` — so every user with a NULL phone (the column is nullable in the DB)
was swept up and destroyed alongside the real matches.

## Why a failed destroy reports to Sentry directly

A failed destroy has to reach an operator, not just sit in a log line.
Sentry's `breadcrumbs_logger` turns `Rails.logger` output into breadcrumbs
— background context attached to some other event — never an alert of its
own. So it reports to Sentry directly, the way `deactivation_url` does
elsewhere in this file.

## Why only a real leading "+" is stripped

Strip ONLY a real leading "+" (the E.164 phone format), never a blind
first character. `slice(1..)` corrupted any un-prefixed line (a blank
line, a header, a format change) into a wrong number that then fed the
`User.where(...).destroy` sweep — a corrupted value colliding with another
user's phone deletes the wrong account. `delete_prefix` is a no-op when
"+" is absent; `compact_blank` drops blank lines so they never reach the
batch.

## Why the "no deactivation file" Twilio error skips PII scrubbing

The `deactivations.fetch` endpoint is keyed by DATE, not by anyone's phone
number, so this Twilio error carries no PII (personal data) —
`log_exception` is safe here.
