---
mode: explanation
summary: "Explains why MAX_OCR_PAGES caps the number of pages the OCR fallback processes, and how the value was chosen."
status: agent-extracted
related: [docs/explanation/pdf-extraction-mutool-ocr-fallback.md]
---
# Why MAX_OCR_PAGES caps the OCR fallback

<!-- vale Vale.Spelling = NO -->

`MupdfExtractor::MAX_OCR_PAGES` bounds how many pages the OCR fallback
will process. It caps the page COUNT, not just how long any single page
is allowed to take.

## Why bounding one page is not enough

Each `Sway::Subprocess` call already carries a 300-second time limit. But
without a page cap, a 400-page scanned bundle could still mean roughly a
33-hour worst case for a single attachment, on the single production
Raspberry Pi, with no watchdog above it. Bounding each subprocess call
without also bounding the page count only turns "hangs forever" into
"hangs for a day and a half" — and on a single-worker Solid Queue, that is
still an outage.

## How 50 pages was chosen

50 pages at 300 DPI is already minutes of Tesseract work on that
hardware, and it is longer than any genuine testimony document found in a
sweep of 797 real attachments. A scan that long is a hearing packet, not
testimony.

## The cap never loses text silently

When the cap cuts pages, the extracted text says so. That follows this
codebase's convention for any cap that discards evidence: the loss is
never silent.
