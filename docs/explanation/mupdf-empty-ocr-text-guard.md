---
mode: explanation
summary: "Explains why MupdfExtractor raises instead of returning empty text when the OCR path recovers nothing."
status: agent-extracted
related: [docs/explanation/pdf-extraction-mutool-ocr-fallback.md]
---
# Why OCR output must never be empty

<!-- vale Vale.Spelling = NO -->

`mutool`'s OCR mode can exit successfully while producing empty output.
`MupdfExtractor.preflight!` only catches causes visible from the
environment. It cannot see a corrupt `.traineddata` file, a wrong-language
pack, or a Tesseract engine that recognizes nothing in the image — all of
those pass preflight and then extract `""`.

## What happened before this guard existed

Treating an empty OCR result as success once let the pipeline save `""`
as a bill's extracted text — in the database and in the on-disk `.md`
file — and mark the extraction stage green. The loss only surfaced two
stages later, at a point where nothing could name its real cause.

## The fix

`MupdfExtractor` now raises `ExtractionFailed` instead. That degrades to
one failed bill with an accurate reason, using the same per-bill error
class the pipeline job already translates
(`RunLegislationPipelineJob#execute_bill_level_service`'s
`rescue MupdfExtractor::ExtractionFailed`).

## Why the check lives here, not at the caller

The sibling extractor guards at its caller instead:
`TestimonyTextExtractor` returning empty text is a documented, supported
outcome at `FetchHearingsService#extract_one_attachment`. For
`MupdfExtractor`, empty text is never an acceptable outcome, so the check
lives inside the class itself.

The native (non-OCR) text path is left alone: a genuinely blank PDF is a
real possible result there, and `MIN_NATIVE_CHARS` already routes short
results into OCR.

## Ordering matters

The truncation notice is appended after the emptiness check runs, never
before. Appending it first would make the non-blank notice text look like
recovered content and defeat the check.
