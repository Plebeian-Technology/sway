---
lat:
  mode: explanation
---

# Why mutool's output is scrubbed for invalid UTF-8 and time-limited

Explains why mutool's output is scrubbed for invalid UTF-8 before it is persisted, and why every subprocess call carries a time limit.

## Why the output is scrubbed

`mutool` emits whatever a PDF's text layer decodes to. A mis-declared encoding inside the PDF can produce bytes that are not valid UTF-8.

`MupdfExtractor`'s output is persisted verbatim: `RunLegislationPipelineJob#execute_extract_text` writes it to `bill.extracted_text` and to `legislation/bills_text/<external_id>.md`. `BillSummaryPromptBuilder#source_present?` then calls `String#present?` on it.

ActiveSupport's `String#blank?` is `empty? || BLANK_RE.match?(self)`, with a rescue for `Encoding::CompatibilityError` only. Invalid bytes raise an unrescued `ArgumentError` instead — which meant an HTTP 500 on the admin "generate summary" request, and three wasted retries on the background-job path.

The fix is to scrub the bytes at the boundary where they enter, the same way the sibling wrapper (`TestimonyTextExtractor`) already does. An earlier fix scrubbed only the sibling and stopped one frame short of this class.

## Why there is a time limit

This is the other `mutool` wrapper next to `TestimonyTextExtractor`, and it once kept the same unbounded `Open3.capture3` call that the sibling had already been fixed to remove.

This is the other `mutool` wrapper next to `TestimonyTextExtractor`, and it once kept the same unbounded `Open3.capture3` call that the sibling had already been fixed to remove — a fix that had been applied to only one of the two matching call sites.

All three subprocess calls in this class (native text, PNG render, Tesseract) now carry `Sway::Subprocess`'s time limit, and `TimedOut` is translated into `ExtractionFailed` at each one, so a stuck subprocess still fails only its own bill.

## Why ExtractionFailed only carries 500 characters of stderr

The message on `MupdfExtractor::ExtractionFailed` carries only the first 500 characters of `mutool`'s stderr.

It is truncated to keep log volume bounded — `mutool`'s stderr is tool diagnostics, not personal data, so there is no confidentiality reason to keep the whole thing, only a size one.

## Why a missing binary is translated the same way as the sibling extractor

`#run_png_render` and `#run_tesseract` each translate a `SystemCallError` (a missing or unexecutable binary) into `ExtractionFailed`, matching the translation the sibling wrapper (`TestimonyTextExtractor`) already had.

`#run_png_render`'s render step is the one that runs when `mutool` was packaged without bundled OCR, so it gets the same absent-binary translation as the rest of the class. `#run_tesseract`'s standalone `tesseract` binary is the likeliest missing binary in the whole class — that fallback runs only when `mutool` was packaged without Tesseract, and a machine in that state very plausibly also lacks the standalone `tesseract` package. Nothing installs or probes for it, and `.preflight!` checks `TESSDATA_PREFIX` only, never a binary.

`#run_mutool`'s own `SystemCallError` rescue exists for the same reason: the sibling wrapper had this translation first, and an earlier sweep copied over the timeout handling but left this clause behind — the fourth time a fix landed in only one of these two matching files.
