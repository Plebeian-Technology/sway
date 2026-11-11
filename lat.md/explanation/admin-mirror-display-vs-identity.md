---
lat:
  mode: explanation
---

# Why the admin testimony mirror keeps a display label separate from identity

`FetchHearingsService#attachment_status_mirror` builds the short per-attachment status list the admin UI shows for a bill's testimony: `{filename, download_status, extraction_status, error}`.

This document explains why that list carries two different-looking fields for what an attachment "is" — `filename` and `attachment_id` — and why neither can stand in for the other.

## What stays out of the mirror entirely

The full attachment record — `id`, `url`, `source_endpoint`, `event_id`, `event_item_id` — stays only in the hearings artifact, not in the admin mirror.

That includes denied records: `#call_discover` unions them back in before writing the hearings artifact file, specifically so their full detail is preserved somewhere even though the mirror only shows a summary.

Content-denied records are appended AFTER the working set in the mirror: stage 3 removed them from the working set, so the mirror is the one place their denial and its reason still show up. They carry `EXTRACTION_STATUS_CONTENT_DENIED`, which is not a contributing status, so `#evidence_withdrawn?` and its `#contributing_entries` filter treat a denied row exactly the way they treat that attachment's absence — a previously contributing attachment that gets denied on a later run still reads as withdrawn.

## filename: a human-readable display label

The `"filename"` key holds a HUMAN-readable name, falling back to the upstream filename only when Legistar carried no name of its own.

The key is still called `"filename"` because it is a display label and the browser already renders it as one, in `LlmSummaryTestimonyAttachmentWarning`. What it holds is chosen so an operator can recognize it and search Legistar for it — something like `"BCFD 25-0064.pdf"` — instead of a random-looking id like `"17b4a1c3-3b40-40e0-a9d1-622d9b150764.pdf"`, which is what all 28 rows in the reference cassette carry as their raw filename. That raw id stays on the full record in the hearings artifact, where origin details belong; it is no use to an operator on the mirror, since the local sidecar file is named `attachment-<id>.pdf` either way.

## attachment_id: the identity, kept separate from the label

The `"attachment_id"` key is the identity, kept deliberately separate from the display label above.

`#evidence_withdrawn?` compares these lists across runs to decide whether a public organization position may still be published, and `"filename"` cannot carry that weight: Legistar does not make names unique. The reference cassette used in tests has fewer distinct names than rows — measured under "the reference cassette the allowlist was read off" in `spec/services/legistar/attachment_url_spec.rb` — and `LlmSummaryTestimonyAttachmentWarning` says exactly that before rendering attachments by position, for the same reason.

## The same split exists one layer down, on the raw attachment record

`FetchHearingsService#normalize_attachment_entry` keeps both `MatterAttachmentFileName` (as `"filename"`) and `MatterAttachmentName` (as `"name"`) on the attachment record itself — the source the mirror above is later built from.

`MatterAttachmentFileName` is a random-looking id on every attachment row in the reference cassette (`17b4a1c3-3b40-40e0-a9d1-622d9b150764.pdf`), never the display name — both measured under "the reference cassette the allowlist was read off" in `spec/services/legistar/attachment_url_spec.rb` — while `MatterAttachmentName` is the name an operator can actually recognize and search for in Legistar (`"BCFD 25-0064.pdf"`). The record keeps both: the id is what the file is called upstream, the name is what it IS.

## Why it is stored as a string

`attachment_id` is stored as a `String` so every value in a mirror entry stays a string or nil. This is a JSON-serialized database column, and letting another type slip in would ripple out to every reader of the column.

## The frontend's ITestimonyAttachment.attachment_id

`FetchHearingsService` writes it on every mirror row it builds from a record, and the server compares it across runs to decide whether a public organization position may still be published.

Declared here for the reason `IOrgPosition.rejected` is declared in its own type: the server can send it, so the type that describes what the server sends should say so.

Optional because two kinds of row carry no id: the made-up rows (truncation, retained testimony, an unswept event or collection), which name no attachment at all, and rows written before this key existed.

## Test notes on the AttachmentRows key

Duplicates are deduped by `MatterAttachmentId`, not filename, and filename is `""` when `MatterAttachmentFileName` is missing. Keying the list on filename squashed separate failures into one row.

The same two-documents-one-name case as production reaches it: the server sends a stable id per row, so the list keys on identity, not on a label Legistar does not keep unique.
