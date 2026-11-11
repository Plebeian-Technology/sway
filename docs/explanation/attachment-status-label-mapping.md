---
mode: explanation
summary: "Explains attachmentStatusLabel.ts: why the Rails status enums are mirrored by hand, why a truncated extraction still counts as succeeded, why the download status outranks the extraction status, and how attachmentDisposition maps both onto the four-list grouping."
status: agent-extracted
related: [docs/explanation/testimony-attachment-warning-lists.md]
---
<!-- vale Vale.Spelling = NO -->

# Why attachmentStatusLabel.ts is built the way it is

## Mirroring the Rails status enums by hand

Mirrors the Rails status enums by hand — the server sends plain `string`,
not an importable type. These lists make the label lookups below
exhaustive: a missing status fails the build, not the row.

## `extraction_failed` covers three causes with one phrase

Covers three causes (no text, disk write failed, extractor raised) with
one phrase; `error` says which.

## `TAttachmentDisposition`: what feeds the prompt, and why not if it doesn't

- `extracted` — full text read.
- `truncated` — cut at the 500,000-char cap; extraction stays "succeeded"
  (it did), cap noted in `error`.
- `reused` — download failed but an earlier run's saved text IS in the
  prompt.
- `no_text` — nothing reached the prompt — the only case pasting helps.
- `denied` — read, ruled not testimony; shown so "withdrawn" isn't
  confused with "reclassified".

Unrecognized, or "succeeded" under a failed download, both count as
`no_text`.

See
[testimony-attachment-warning-lists.md](testimony-attachment-warning-lists.md)
for why the UI groups these into four separate lists rather than one.

## `attachmentDisposition`: why extraction stays "succeeded" on truncation

On a succeeded/succeeded pair, `error` alone signals truncation vs a full
read — extraction stays "succeeded" on purpose so `!== "succeeded"` checks
elsewhere still see it as fine.

## `EXTRACTION_OUTRANKS_DOWNLOAD`

Both come from an EARLIER run's saved copy, so this run's own download can
fail while the text is still real. `content_denied` used to be missing,
showing "not testimony" beside "download failed".

## Test notes

`EXTRACTION_STATUS_FAILED` covers three causes (no text layer, write
failure, extractor raising twice), so the label says what to do — "could
not extract text" — leaving the reason to `error`.

A content-denied document must stay visible: dropping its row let an
all-denied run clear stored testimony with no attachment, warning, or
reason shown anywhere.

The classifier judges from an earlier run's saved text, so a
failed-download document can still be judged — but the row said both
"read and judged" and "download failed", contradicting itself.

Truncation keeps `extraction_status` "succeeded" and notes the shortfall
only in `error` — a row the component never rendered before.

## Why the download problem wins when both statuses have something to say

When both statuses have something to say, the download problem wins — the
extraction status can only repeat it back as "not extracted — download
failed".
