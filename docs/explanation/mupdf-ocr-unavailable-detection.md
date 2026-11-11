---
mode: explanation
summary: "Explains why OcrUnavailable is a separate exception class and the substring-matching bug it replaced."
status: agent-extracted
related: [docs/explanation/pdf-extraction-mutool-ocr-fallback.md]
---
# Why OcrUnavailable is a separate exception class

<!-- vale Vale.Spelling = NO -->

`MupdfExtractor::OcrUnavailable` means this machine's `mutool` was
packaged without bundled OCR. It is a subclass of `ExtractionFailed`, so
every existing `rescue ExtractionFailed` still catches it — no caller had
to learn a new class. What the subclass adds is that `#run_ocr` can now
pick this failure out by its class, instead of searching for a substring
inside a message whose length it does not control.

## The exact signature string

`OCR_DISABLED_SIGNATURE` is the exact string `mutool` writes to stderr when
it was compiled without OCR (`HAVE_LEPTONICA=no HAVE_TESSERACT=no` — true
of both Debian trixie's and Alpine's `mupdf-tools`).

## The bug that substring matching caused

That substring search used to be a real bug. The exception's message only
ever carried the first 500 characters of stderr. `mutool` prints one
warning line per malformed PDF object while it parses the file — before
the draw step that reports "OCR Disabled in this build". A messy enough
PDF could push that signature past character 500, so the code read it as
some unrelated `mutool` failure instead.

## Why a missed detection is expensive

The detection is remembered per worker process, so the doomed
mutool-OCR attempt happens only once per worker. Without that memo, every
image-only bill would retry the same doomed attempt, until the pipeline's
consecutive-failure budget force-failed the whole run — the exact
situation this fallback exists to prevent.

## Why the OutputTooLarge path reads e.stderr instead of the discarded stream

`#run_mutool`'s `rescue Sway::Subprocess::OutputTooLarge` raise discards
the stream, so the OCR-disabled signature has to be read off the
exception's bounded copy of stderr before the translation — a 256 KiB
flood of parse warnings must not be able to turn "mutool has no OCR" into
"some large output".

## Why the signature match always reads the FULL stderr, not a truncated copy

`OCR_DISABLED_SIGNATURE` is always tested against the WHOLE scrubbed
stderr, and the answer travels in the exception's CLASS rather than in a
substring search on the message. The message stays capped at 500 characters
for the log — which is exactly what used to swallow the decision: matching
on the message could not see a signature that mutool's per-malformed-object
warnings had pushed past the cap.
