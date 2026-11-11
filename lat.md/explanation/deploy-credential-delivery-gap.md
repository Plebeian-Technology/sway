---
lat:
  mode: explanation
---

# Why credential delivery to production is checked separately

`EnvCredentialScanner` already knows which names are credentials the app reads, and `spec/lib/env_secret_coverage_spec.rb` checks each one is TRIMMED.

Nothing checked the other half: whether a credential the app reads is DELIVERED to the machine that runs it — listed in `config/deploy.yml`'s `env.secret` (or `env.clear`, for a non-secret value).

## The gap was not hypothetical

A secret declared in the store but not listed in `env.secret` never reaches the container. A credential that signs mobile bearer tokens, left off that list, fails every bearer request, and only a manual check notices.

The scanner even lists the APNs and FCM names under `EXTRA_CREDENTIALS`, described as credentials that do not come from `.kamal/secrets-common` — the knowledge was written down and never connected to anything that checked it.

## The fix

`spec/config/deploy_yml_spec.rb`'s "credential delivery" examples cross-check `EnvCredentialScanner.new.credential_names` against what `config/deploy.yml` actually delivers (`env.secret` plus `env.clear`'s keys).

A name in neither list, and not explicitly excused in `EnvCredentialScanner::UNDELIVERED_CREDENTIALS` (with a reason), fails the build. A second example catches the opposite drift: an entry left in `UNDELIVERED_CREDENTIALS` after the credential was actually wired up, since a stale "we do without this" note is worse than none — it tells the next reader a live credential is still optional.

The reasons for each undelivered credential live beside `EnvCredentialScanner`'s other annotated credential lists, not in this spec, so every "why this name is treated specially" fact sits in one file.

## Delivered does not mean usable: TWILIO_FROM_PHONE

`TWILIO_FROM_PHONE` is listed in `env.secret` and `.kamal/secrets-common`, so `SmsDeliveryJob` has a from-number and does not return early for that reason.

Delivery does not mean notification SMS sends: the Twilio account must also be approved to send, such as through A2P 10DLC campaign registration, or the Twilio Messaging API rejects sends regardless of the from-number being present. The `config/deploy.yml` entry for `TWILIO_FROM_PHONE` carries a DOCREF pointer back to this section.
