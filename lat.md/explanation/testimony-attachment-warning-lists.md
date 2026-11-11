---
lat:
  mode: explanation
---

# Why the testimony attachment warning has four lists, not one

`LlmSummaryTestimonyAttachmentWarning` points out attachments whose testimony failed to download, or whose text failed to come out. It never stops anyone saving or approving: warning styling, never the red used for errors.

There are three separate lists, because there are three different answers.

## "Paste it in" only fits documents whose text never reached the prompt

That is the `missing` list.

A `reused_prior_run` row is different: its text IS in `extracted_testimony` and IS in the positions prompt (see [[docs/explanation/testimony-mirror-rule.md|the testimony mirror rule]]), so filing it under "attachment issues … paste the testimony text below" made the operator feed the positions call the same testimony twice, from two different sources, on a row whose own error message said the text was already captured. That is why `reused` gets its own list with different wording, not a place in `missing`.

## A cut-short extraction is a third answer

The document's text is in the prompt but truncated, so neither "re-paste this document" nor saying nothing is true.

It used to say nothing: a row where both the download and the extraction steps succeeded was sorted as `extracted`, which no list drew, so `FetchHearingsService`'s truncation note was written onto a row that never appeared on any screen. `truncated` exists to give that row a place.

## A content-denied document is the fourth answer

The classifier read it and judged it not testimony, so its text is deliberately withheld — the system working, not a failure.

It still gets its own list, because without one the document simply vanished: in the all-denied case the run cleared the stored testimony with no attachments, no warning, and no reason anywhere an admin could see. `denied` exists to make that outcome visible.

## Test notes

Typing into Supplemental testimony saves nothing by itself — only Save testimony (or Generate/Regenerate) sends it. The notice must name the click, not just the field.

`FetchHearingsService` writes 5 download and 7 extraction statuses; the component squashed them into one failure label. Most are not failures, and `reused_prior_run` means the text IS in the prompt.

`reused_prior_run` means this run's extraction failed, but an earlier run's `.txt` file still feeds `extracted_testimony`. Listing it as an issue to re-paste would feed positions the same text twice.

## Why AttachmentAlert is one shared shell

The shape every one of the lists draws: a heading, the rows, and one sentence saying what to do about them.

Only the styling, the id, the heading and that sentence differ, and writing the shell out four times meant four places to keep in step.

## attachmentCountText.ts centralizes the plural/count wording

Centralizes plural/count wording so the four alerts in `LlmSummaryTestimonyAttachmentWarning` don't each spell it differently. Threshold: more than one; zero never reaches these.

## Why countNoun is separate from attachmentCountText

[[app/frontend/sway_utils/countNoun.ts#countNoun]] formats zero and two-or-more with the plural noun and one with the singular noun.

[[app/frontend/components/admin/creator/llm-summary/attachmentCountText.ts#plural]] returns the singular form at zero because zero never reaches the attachment warning alerts. Keeping `countNoun` separate avoids changing the behavior of `attachmentCountText.ts` for screens that can render zero.
