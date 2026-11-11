---
lat:
  mode: explanation
---
# Legislator photo orphan cleanup

Stored Legislator portraits are purged when their owner row is retired or absent, while live photos and shared blobs remain available.

## Orphan photo cleanup and merge deletion

Bulk-deleting a Legislator can leave its photo attachment behind because Active Storage has no owner foreign key.

[[lib/legislator_photo_purger.rb#LegislatorPhotoPurger]] scopes the repeatable task to `record_type = Legislator` and `name = photo`, uses a `NOT EXISTS` anti-join, and refuses a sweep above one quarter of the scoped photos unless the task receives its explicit force argument. Force changes only that size cap; it does not bypass the owner check.

The same class rechecks that the attachment still belongs to the requested owner state immediately before synchronously purging it. A merge instead passes the retiring IDs in `:present` mode just before its callback-free row deletion. The four maintained merge paths are [[db/data/20260711000004_convert_duplicate_legislators_to_terms.rb#ConvertDuplicateLegislatorsToTerms#up]], [[db/data/20260801000001_merge_baltimore_seat_rows.rb#MergeBaltimoreSeatRows#delete_row]], [[db/data/20260803000001_finish_merging_baltimore_seat_rows.rb#FinishMergingBaltimoreSeatRows#delete_row]], and [[db/data/20260812000001_join_baltimore_council_rows_to_one_person.rb#JoinBaltimoreCouncilRowsToOnePerson#up]].

The bulk `delete_all` calls bypass row callbacks, while Active Storage's `Attachment#purge` still follows the framework path and touches its owner. That touch does not change `photo_url`, so the mirror callback does not enqueue a download. Purge is synchronous; a later database rollback cannot restore a file already removed from storage. When another attachment still references the blob, Active Storage retains that blob and file. The regression coverage is in [[spec/tasks/legislator_photo_orphan_cleanup_spec.rb]].

The final seat-row merge removes derived score rows before their terms and terms before the person, preserving foreign-key dependencies during deletion. Its photo purge changes attachment handling without changing that deletion order.
