---
mode: explanation
summary: "Explains how FetchHearingsService orchestrates stage 3 (reading extracted document text to classify undecided attachments), and its two denial dispositions."
status: agent-extracted
related: []
---
# Stage 3: classifying attachments by their extracted text

<!-- vale Vale.Spelling = NO -->

`Testimony::AttachmentClassifier` classifies in three steps, and this is the
last of them.
This document covers how `FetchHearingsService` orchestrates that stage —
`#testimony_verdicts`, `#classify_attachment_contents!`,
`#mark_content_denied`, `#mark_content_unreadable`, and
`#content_verdict_keeps?` — moved BELOW download and extraction so the
model judges the DOCUMENT rather than its file name.

## Why stage 3 runs after extraction, not inside discovery

A candidate reaches stage 3 precisely because its name was uninformative —
`Testimony::NameRules` answered `:undecided` for it — so the old ordering,
which classified inside `#discover_attachments` on the name alone, could
not do the job stage 3 exists for. Measured over the on-disk hearing corpus
(1,429 distinct attachment names — see
`rake sway:measure:classification_corpus`), about 32% land in this
undecided set.

`#testimony_verdicts` runs stages 1 and 2 only (the name rules and the
cached verdicts) — before a single byte is fetched, which is the whole
cost argument: a name-denied attachment is still never downloaded, never
extracted, and never sent to a model. What it cannot do is settle the
leftover undecided names, because settling those requires reading the
document. Those ids are parked on `@content_pending_ids` for
`#classify_attachment_contents!`, which runs after extraction.

An undecided id is deliberately ABSENT from `#testimony_verdicts`'s
returned map rather than present as `true`: `#keep_entry?` already defaults
a missing id to keep, so "not yet decided" and "decided keep" stay
distinguishable even though they lead to the same download.

## THE TEXT COMES FROM THE SIDECAR

`#classify_attachment_contents!` reads the `.txt` sidecar — not
`#extract_attachments!`'s return value — and that is load-bearing in two
directions:

- It is the same reader and the same path `#compose_testimony_from_disk`
  uses, bounded at `CLASSIFICATION_READ_BYTES` (see
  `docs/explanation/testimony-composition-size-limits.md`), so the document
  is judged on the opening of exactly the text that would reach the
  positions prompt.
- A record whose extraction FAILED this run but whose PRIOR run's sidecar
  is still contributing (`EXTRACTION_STATUS_REUSED`) is classified on that
  text rather than silently skipped.

## Two dispositions, and they are not symmetric

- **CONTENT-DENIED** — the model read the document and said `not_testimony`.
  The record is REMOVED from the working set, exactly as a name-denied
  candidate never entered it. Removal is what stops its sidecar reaching
  `#compose_testimony_from_disk`; leaving the record in and merely marking
  it would put the text the model just rejected straight into
  `extracted_testimony` — the exact leak this whole filter exists to stop.
  The denial is still VISIBLE: the removed records are kept on
  `@content_denied_records` with the status and reason
  `#mark_content_denied` writes, and `#attachment_status_mirror` appends
  them to the admin list. The message it writes says the one
  thing an operator can actually do: a saved verdict is re-asked only when
  the classification prompt changes, so a wrong denial is worked around by
  pasting the testimony in by hand.
- **UNREADABLE** — no sidecar text when stage 3 asked (extraction failed,
  the download failed, or a budget ran out). Denied, because admitting a
  document nobody could read asserts evidence never seen; but the record is
  KEPT in the working set, because dropping it would delete the only
  operator-visible trace of it. Keeping it is safe because the id is
  remembered on `@content_unreadable_ids` and
  `#compose_testimony_from_disk` skips it — that memory is the guarantee,
  not the blank read itself. This read and composition's are two separate
  reads of the same path at different times, so a transient read failure —
  or another process writing the sidecar — could otherwise make the file
  readable again by composition time and feed text no model ever judged
  into `extracted_testimony`. `#mark_content_unreadable` also
  squares the admin mirror: a record still claiming a CONTRIBUTING
  extraction status is rewritten to `extraction_failed`, so the mirror
  never advertises text the composition withholds, and
  `LlmSummaryTestimonyAttachmentWarning` shows the row as "paste this by
  hand".

## `#content_verdict_keeps?`: reading the three guard clauses as guards

Split out of `#classify_attachment_contents!` so its three "not this
record's business" exits read as the guards they are, rather than as one
tangled condition:

- No id — never classified, never had a cache key, and
  `#normalize_attachment_entry` already recorded it as a failed download.
  Its siblings must still show up for the operator, and so must it.
- Not in `@content_pending_ids` — its stage 1/2 verdict already settled the
  question; stage 3 has nothing to add.
- In `@content_unreadable_ids` — denied, but retained; see UNREADABLE
  above.
- Otherwise, a missing verdict from the classifier is the fail-open
  default: the model was asked and did not answer for this index, or the
  call failed entirely. Same posture as
  `Testimony::AttachmentClassifier#fallback_verdicts`.

Never raises: `#classify_contents` is fail-open by contract and everything
in `#classify_attachment_contents!` is set arithmetic over records already
in hand.
