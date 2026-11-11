---
lat:
  mode: explanation
---

# Why MAX(id) was the wrong tie-break for duplicate classifications

The duplicate collapse in `KeyTestimonyClassificationsOnAttachmentId` used `MAX(id)`, which keeps whichever row was inserted last.

Insertion order is not the same as recency here: `Testimony::AttachmentClassifier#persist_verdict` does `find_or_initialize_by(attachment_id:)` and then `save!`, so an existing row is updated in place — its id never changes while its label does. A later, corrected re-classification that updates an *older* row in place therefore loses to an earlier, never-updated row with a *higher* id, and the migration permanently deleted the corrected verdict and kept the stale one. The cache this table feeds never expires, its read check ignores which prompt and model produced the row, and nothing invalidates it, so the loss lasted as long as the database did.

Concretely, for one attachment (38947):

```
run 1  surfaces from event_item_matter_attachments
       -> row id=1, label="not_testimony"  (a Haiku miss)
run 2  the event fetch 500s, so it surfaces from matter_attachments
       -> row id=2, label="not_testimony"
run 3  the prompt is improved and the event fetch succeeds again
       -> row id=1 is UPDATED to label="testimony"
```

`MAX(id)` is 2, so the old ordering kept the stale `not_testimony` and deleted the corrected verdict — losing evidence, which is the wrong direction to fail in for a cache with no operator remedy short of hand-written SQL.

The migration's fix orders by `updated_at DESC`, then breaks a genuine timestamp tie two ways: `label = 'testimony'` wins first (fail-open is this subsystem's posture everywhere else, and a tie means neither verdict is more recent), then `id DESC` purely so the result is deterministic.

## Why attachment_id alone, not (source_endpoint, attachment_id)

The migration this one replaces (`20260725000001`) keyed the cache on `(source_endpoint, attachment_id)`, on the premise that a `MatterAttachmentId` and an `EventItemMatterAttachment` id occupy different Legistar id spaces.

That premise is false: decoding `spec/cassettes/legistar_testimony_endpoint_probe.yml` shows all 28 `MatterAttachmentId`s of matter 10122 appear verbatim inside the `EventItemMatterAttachments` arrays of Events/5065/EventItems — `EventItemMatterAttachments` is a projection of `MatterAttachments`, not a parallel id namespace.

Which collection surfaced an attachment depends only on whether that event's per-event fetch happened to succeed, so scoping the key by `source_endpoint` re-billed the same attachment and wrote a second row whenever the fetch flipped. `source_endpoint` stays on the row as provenance; it just stops participating in identity.

`KeyTestimonyClassificationsOnAttachmentId` (`20260725000002`) is a new migration rather than an edit to `20260725000001` because other development databases had already run that one, and the phase it belongs to had not yet reached production — so no production rows existed under either scheme at the time.

## Testing against a schema that has already moved on

The spec is built like `spec/data/convert_duplicate_legislators_to_terms_spec.rb` (see [[docs/explanation/legislator-term-conversion-fixture-design.md|its fixture design]]).

The spec is built like `spec/data/convert_duplicate_legislators_to_terms_spec.rb` (see [[docs/explanation/legislator-term-conversion-fixture-design.md|its fixture design]]): the test schema is already in its post-migration state (the unique `attachment_id` index is there), so that shape has to be undone before the fixture can insert duplicate rows, then put back afterward. A later migration (`20260810120000`) went further still, replacing the `attachment_id`-only unique index with a composite `(sway_locale_id, attachment_id)` index and adding `sway_locale_id NOT NULL` — because Legistar runs one instance per city, and attachment 38947 means a different document in each city. The spec's `before`/`after` hooks restore whichever index shape the migration under test actually produces, not whatever the current schema.rb happens to hold, or the next spec to touch the table pays for a state no migration produces.

## Why every row in the spec uses one locale, tracked for cleanup

Every fixture row in this spec uses the SAME `SwayLocale`: `sway_locale_id` did not exist when the migration under test ran, so a fixture that varied it would be asking the migration a question it was never written to answer.

This file runs with `use_transactional_tests = false`, so nothing it creates is rolled back automatically — everything it inserts is left in the shared test database for every later example. A leaked `SwayLocale` is not harmless: the `sway_locale` factory hands back an EXISTING row when one matches, so a later spec that expects the factory's own `current_session_start_date` silently gets this row's instead, and a job scoped to "bills in the current session" then sees fewer bills than the spec set up. That is why `#created_sway_locale` is tracked and the `after` hook removes it — but only when this file is what created the row; one that was already there belongs to whoever made it.

## Why every helper name in this file starts with testimony_classification

`sig-test`'s `object_spec_methods.rbs` declares one Steep signature per helper name for the whole spec suite, not per file.

A bare `insert_row` or `run_migration` helper here would collide with any other spec file that wanted the same name for something else, so every helper in this file is namespaced with a `testimony_classification` prefix instead.
