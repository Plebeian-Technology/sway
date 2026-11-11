---
lat:
  mode: explanation
---

# Why there is no primary: true flag on testimony attachment candidates

`FetchHearingsService#discover_attachments` builds the candidate list of testimony attachments for a matter.

This document explains a filter it deliberately does not have, and why adding it back would delete real testimony rather than protect against bill text.

## What the flag was

A `primary: true` flag used to ride on each attachment record.

A `primary: true` flag used to ride on each attachment record — a local copy of `FetchBillsService#select_primary_attachment`, marking "the attachment the bill-text stage will take." It was written onto the record and never read anywhere. A code review that noticed this asked for it to be enforced instead of deleted: reject any candidate that is also the bill-text pick.

## Why enforcing it was the wrong fix

The flag measures the wrong thing for that job:

- **"The bill-text stage took it" is not the same claim as "it is bill
  text."** On a matter with no Reader-named attachment, the bill-text pick
  comes from `FetchBillsService#select_primary_attachment`'s fallback,
  `#best_non_testimony_pdf`. Both methods' own docstrings record why: the
  rule that fallback replaced took the newest-modified PDF, and it
  reliably picked the WRONG document — supporting attachments get uploaded
  for months after the bill text is final, so on a matter with no Reader
  the newest PDF is usually testimony, not the bill. That means the
  `primary: true` flag could fire on genuine testimony.

Those two method names — `FetchBillsService#select_primary_attachment` and `#best_non_testimony_pdf` — are cited here on purpose. An earlier version of this note pointed at a line range in `fetch_bills_service.rb` instead, and that range had drifted about 170 lines onto unrelated code about `MatterFile` sanitization. A reader checking the counter-argument found unrelated code there and could reasonably conclude the argument had no evidence behind it. Citing the method names instead of line numbers survives refactors that citing line ranges does not.

- **The underlying rule is broken specifically when bill text reaches the
  positions prompt.** A community letter of support reaching the positions
  prompt is the testimony-discovery rule working correctly. The defect in
  that other case is on the bill-text side — the bill's own summary gets
  built from a letter instead of the bill text — and this class cannot fix
  a bill-text-selection defect from the testimony side.

- **Rejecting on the flag measurably deleted real testimony.** Enforcing
  the flag emptied the candidate set for every single-PDF matter, because
  on a matter with only one PDF attachment, that attachment is trivially
  its own "primary" pick — while leaving the summary prompt just as
  polluted as before, since the real defect was never on this side.
  Surfacing the ambiguity on the admin mirror instead put a warning row on
  that same broad class of ordinary bills, without deleting evidence.
 

## What replaced it

The flag was deleted rather than left in place, on the principle that an unread flag is a trap for a future reader, and a private copy of another class's selection algorithm silently drifts from the original over time.

Bill text is kept out of the testimony candidate set by three other mechanisms instead, all inside `#discover_attachments`:

1. `Testimony::NameRules::BILL_TEXT_PATTERNS` — non-overridable, stage 1 of
   the filter.
2. `Testimony::NameRules::AMBIGUOUS_BILL_TEXT_PATTERNS` — denies a name
   unless it also hits the testimony allowlist.
3. Stage 3's LLM verdict (see `docs/explanation/hearing-fetch-pipeline.md`
   for why that verdict runs after extraction, not before).

That trio is the only thing keeping bill text out of the positions prompt.

## Why the .pdf gate cleans the name before testing it, and what it replaced

`FetchHearingsService#pdf_attachment?` is a file-type check and nothing more: `.pdf`, tested against `Legislation::Paths.upstream_file_name`'s cleaned-up `MatterAttachmentFileName`.

It used to be the WHOLE testimony filter — `.pdf` plus "the name does not match `FetchBillsService::READER_NAME_PATTERN`". Measured against the real Legistar API (25 bills / 415 attachments, plus a 60-bill / 797-attachment sample), that combination let 87% of ALL attachments through: `Ord.25-063 tc`, `25-0064 Signed`, `cc25-0064(1)~1st (LUT)` and `cc25-0064(1)~1st (Gray)` all slip past a Reader-name pattern, so bill text was reaching the positions prompt — the one thing this filter exists to prevent. Deciding what counts as testimony is now `Testimony::AttachmentClassifier`'s job instead.

`FetchBillsService#pdf_attachment?` asks the same `.pdf` question the same way, but on `MatterAttachmentFileName` rather than `MatterAttachmentName`. It did not always: `FetchHearingsService`'s side cleaned the name before testing it and `FetchBillsService`'s side read the raw string, so the two services disagreed about which files were PDFs until that was repaired.

Cleaning before the test also keeps this gate and `#normalize_attachment_entry` agreeing about what the file is called. Testing the raw string instead would let `"report.pdf"` with a trailing NUL byte fail the test and be silently dropped, while `"x<NUL>.pdf"` would pass it and then raise later on the way to a file path.
