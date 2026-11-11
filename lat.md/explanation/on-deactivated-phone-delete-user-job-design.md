---
lat:
  mode: explanation
---

# Why OnDeactivatedPhoneDeleteUserJob is shaped the way it is

Why OnDeactivatedPhoneDeleteUserJob batches with compact + each_slice instead of in_groups_of, strips only a real leading +, reports destroy failures to Sentry directly, and treats the deactivation-date Twilio error as PII-free.

## Why batching uses compact + each_slice, not in_groups_of

`in_groups_of(200)` pads the final group with nils, and `User.where(phone: [..., nil])` compiles to `phone IN (...) OR phone IS NULL`.

`in_groups_of(200)` pads the final group with nils, and `User.where(phone: [..., nil])` compiles to `phone IN (...) OR phone IS NULL` — so every user with a NULL phone (the column is nullable in the DB) was swept up and destroyed alongside the real matches.

## Why a failed destroy reports to Sentry directly

A failed destroy has to reach an operator, not just sit in a log line.

Sentry's `breadcrumbs_logger` turns `Rails.logger` output into breadcrumbs — background context attached to some other event — never an alert of its own. So it reports to Sentry directly, the way `deactivation_url` does elsewhere in this file.

## Why only a real leading "+" is stripped

Deactivation lines are validated as E.164 or 10-to-11-digit numbers and normalized to 10-digit US numbers via `normalize_phone`, rather than blindly slicing the first character.

`slice(1..)` corrupted any un-prefixed line (a blank line, a header, or a format change) into a wrong number that fed the `User.where(...).destroy` sweep. Matching `/\A\+?\d{10,11}\z/`, normalizing with `normalize_phone` (which strips a leading US country code `"1"` on 11-digit E.164 strings like `"+14105556789"`), and keeping only 10-digit numbers ensures the sweep matches `User#phone` while dropping headers and blank lines safely. Each matched user also has active device tokens revoked via `revoke_all_devices!` before `destroy`.

## Why the "no deactivation file" Twilio error skips PII scrubbing

The `deactivations.fetch` endpoint is keyed by DATE, not by anyone's phone number, so this Twilio error carries no PII (personal data) — `log_exception` is safe here.
