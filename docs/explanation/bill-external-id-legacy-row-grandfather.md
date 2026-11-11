---
mode: explanation
summary: "Explains why the Bill#external_id format validation runs only on change (if: :external_id_changed?), grandfathering two known-bad production rows instead of blocking unrelated saves on them."
status: agent-extracted
related: [docs/explanation/bill-external-id-validation.md]
---
# Grandfathering two legacy external_id rows

<!-- vale Vale.Spelling = NO -->

`Bill`'s `external_id` format validation (see
[Bill external ID validation](bill-external-id-validation.md) for why the
value needs checking at all) runs only when `external_id` is set or
changed (`if: :external_id_changed?`), not on every save. This is a
deliberate decision about two rows already in production, pinned so it
cannot change unnoticed.

## The two rows

Production holds exactly two rows this format check would reject as they
stand: bill 58, external_id `"\t24-0599"`, and bill 59, external_id
`"\t24-0592"`, both created 2024-11-20. Neither does anything — `active: 0`,
no extracted text, no provisioning row, no `pipeline_run_bills`, `parsed_at`
`NULL` — so no file path was ever built from either, and there was no
migration to fix them until the data migration repaired both rows.

## Why the check is conditional

Checking the format on every save would turn "update an unrelated column on
one of those rows" into a `RecordInvalid` — a validation added for security
would quietly break a backfill on a row nobody is touching for its
`external_id`.

Instead, a `before_validation` strip repairs the value on the next save. An
audit confirmed no other bill uses either stripped id, so the repair cannot
point two bills at one path. The format check itself runs only when
`external_id` is set or changed, so an old row that is neither touched nor
repairable still saves.

## Why the strip runs before the format check, not instead of it

`normalize_external_id` trims whitespace and nothing else — it does not
drop a stray `/` or rewrite a `..`. Any further change there would silently
alter which bill the value names, and a value that hostile has to be
REFUSED by the format check below, not patched up by the normalizer. The
trim runs first so the stored value, its filesystem folder name, and the
Legistar query filter that looks it up never disagree about which bill is
meant — only whitespace, which none of those three readers treats as
significant, is repaired automatically.

## Callback placement

`before_validation :normalize_external_id` is declared immediately after
`before_validation :downcase_status` on the model, because Rubocop's
callback-order cop expects `before_validation` callbacks listed in the
order they run.
