---
lat:
  mode: explanation
---

# Bill external ID normalisation

A bill's `external_id` is path-checked on the way in, and whitespace-stripped before validation. Format checking runs only on change to avoid turning unrelated column updates on legacy rows into write failures.

## Why the check is conditional

Format validation runs only when `external_id` is set or changed (`if: :external_id_changed?`), so updating an unrelated column on an existing row does not fail.

Production historically held two rows with leading tab characters in `external_id`: Bill 58 (`"\t24-0599"`) and Bill 59 (`"\t24-0592"`), both created in November 2024. A data migration strips their leading whitespace and sets authoritative upstream statuses.

Its current lookup also matches the same normalized external IDs in other jurisdictions. The planned correction scopes the repair to Baltimore identity, preserving same-numbered bills elsewhere. A fixture from another locale is needed to prove that boundary.

The conditional format check survives the repair because a validation added for path security should judge what a writer is proposing to change rather than blocking an unrelated update on a row already stored.

## Why the strip runs before the format check

`normalize_external_id` trims whitespace and nothing else before validation runs, allowing safe whitespace cleanup without masking path traversal attacks.

`normalize_external_id` trims whitespace and nothing else — it does not drop a stray `/` or rewrite `..`. Any further change would silently alter which bill the value names, and a value that hostile must be rejected by the format check, not patched up by the normalizer. The trim runs first so the stored value, its filesystem folder name, and the Legistar query filter that looks it up never disagree about which bill is meant.

## Callback placement

`before_validation :normalize_external_id` runs after `downcase_status` to satisfy callback execution order.

`before_validation :normalize_external_id` is declared immediately after `before_validation :downcase_status` on the model, because RuboCop's callback-order cop expects `before_validation` callbacks listed in the order they run.
