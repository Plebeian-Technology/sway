---
lat:
  mode: explanation
---

# Why TestimonyTextExtractor is a separate, OCR-free class

`TestimonyTextExtractor` pulls native text out of a hearing-testimony PDF without falling back to OCR, either through `pdf_extractor_url` (`disable_ocr: true`) or by running one local `mutool draw -F txt` command.

## Why it does not reuse or extend MupdfExtractor

`MupdfExtractor` (see [[docs/explanation/pdf-extraction-mutool-ocr-fallback.md|Why MupdfExtractor tries native text first and falls back to OCR]]) checks for OCR language data when running locally and switches to OCR whenever a PDF holds less than `MIN_NATIVE_CHARS` of real text, raising `ExtractionFailed` if the resulting text is blank.

The testimony path must not depend on OCR at all, and a scanned testimony PDF with no text layer legitimately extracts as `""`. When `Sway::Settings.legislation.pdf_extractor_url` is configured (as on the production Raspberry Pi, where `mutool` runs on the host via `ops/pdf-extractor` rather than inside the Rails container), `#call` posts `{pdf_path: @pdf_path, disable_ocr: true}` to `/extract` and returns the scrubbed text directly, including `""`. When `pdf_extractor_url` is unset, `#call` runs `mutool draw -F txt` once locally and hands back whatever text comes out. Deciding whether an empty or very short result means "this PDF has no text in it," and retrying once, is the CALLER's job — that is the loop that fetches hearing attachments, which also records which attachment failed.

Nothing is remembered between calls: no cached class-level state, and no OCR or language-data setup anywhere.

## Why every failure becomes ExtractionFailed

Both `#extract_remote` and `#run_mutool` turn every failure below into `ExtractionFailed` on purpose. The caller catches only that one exception; anything else kills the whole pipeline run instead of failing a single attachment.

On the remote path, non-2xx HTTP responses, `Timeout::Error`, and network or JSON errors are scrubbed, truncated to 500 characters, and raised as `ExtractionFailed`. On the local path, `Sway::Subprocess.capture3` raises `Errno::ENOENT` when `mutool` is not installed, so every `SystemCallError` is translated too.

The command runs through `Sway::Subprocess` (see [[docs/explanation/subprocess-bounded-execution.md|Why Sway::Subprocess exists]]) so it has a time limit. Plain `Open3.capture3` waits forever, and a malformed PDF that sent `mutool` spinning once stalled this step indefinitely — twice over, since the caller retries once. The timeout error is an ordinary `StandardError`, so it needs the same translation, or it slips past the caller's rescue.

Output size is capped as well as time (see [[docs/explanation/subprocess-output-capping.md|Why Sway::Subprocess caps stdout and stderr]]). A damaged cross-reference table — common in scans uploaded by the public — can pour hundreds of megabytes of error output out well within the time limit and exhaust the memory of the single background worker on the Pi. `Sway::Subprocess` limits both streams; translating that error here is what keeps hitting the cap a single failed attachment, shown with a reason on the admin screen, rather than a dead pipeline run.

## Why the output is UTF-8 scrubbed here

`mutool` prints whatever the PDF's text decodes to, and a PDF submitted by the public with a broken or mislabelled encoding produces bytes that are not valid UTF-8 (see [[docs/explanation/utf8-scrub-rationale.md|Why Sway::Utf8.scrub exists]]).

Nothing further down checked them, so they were written to a sidecar file, saved into `extracted_testimony`, and eventually handed to a regular expression in the positions prompt builder — which raised, outside the rescue guarding that call, and marked an already-finished summary as failed. Cleaning the bytes here, where they first enter the app, gives every later step the same guarantee.
