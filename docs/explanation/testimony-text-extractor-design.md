---
mode: explanation
summary: "Why TestimonyTextExtractor is a separate, OCR-free class from MupdfExtractor, and why every subprocess failure it can hit is translated into its own ExtractionFailed error."
status: agent-extracted
related: [pdf-extraction-mutool-ocr-fallback, subprocess-output-capping, subprocess-bounded-execution, utf8-scrub-rationale]
---
<!-- vale Vale.Spelling = NO -->

# Why TestimonyTextExtractor is a separate, OCR-free class

`TestimonyTextExtractor` pulls the text out of a hearing-testimony PDF by
running one `mutool draw -F txt` command. Nothing more. It never falls back
to OCR (reading text off an image of a page).

## Why it does not reuse or extend MupdfExtractor

`MupdfExtractor` (see
[Why MupdfExtractor tries native text first and falls back to OCR](pdf-extraction-mutool-ocr-fallback.md))
checks for OCR language data when it is created and raises
`MissingTessdataError` when `TESSDATA_PREFIX` is not set — which it is not
on the production Raspberry Pi. It also switches to OCR by itself whenever
a PDF holds less than `MIN_NATIVE_CHARS` of real text. The testimony path
must not depend on OCR at all, so neither behavior is welcome here.

`#call` runs the command exactly once and hands back whatever text comes
out, including an empty string. Deciding whether an empty or very short
result means "this PDF has no text in it," and retrying once, is the
CALLER's job — that is the loop that fetches hearing attachments, which
also records which attachment failed.

Nothing is remembered between calls: no cached class-level state, and no
OCR or language-data setup anywhere.

## Why every failure becomes ExtractionFailed

`#run_mutool` turns every failure below into `ExtractionFailed` on purpose.
The caller catches only that one exception; anything else kills the whole
pipeline run instead of failing a single attachment.

`Sway::Subprocess.capture3` raises `Errno::ENOENT` when `mutool` is not
installed — a real possibility on the small production host, since nothing here
checks for it up front (this class skips `MupdfExtractor`'s check, which
would insist on OCR language data). So every `SystemCallError` is
translated too.

The command runs through `Sway::Subprocess` (see
[Why Sway::Subprocess exists](subprocess-bounded-execution.md)) so it has a
time limit. Plain `Open3.capture3` waits forever, and a malformed PDF that
sent `mutool` spinning once stalled this step indefinitely — twice over,
since the caller retries once. The timeout error is an ordinary
`StandardError`, so it needs the same translation, or it slips past the
caller's rescue.

Output size is capped as well as time (see
[Why Sway::Subprocess caps stdout and stderr](subprocess-output-capping.md)).
A damaged cross-reference table — common in scans uploaded by the public —
can pour hundreds of megabytes of error output out well within the time
limit and exhaust the memory of the single background worker on the Pi.
`Sway::Subprocess` limits both streams; translating that error here is what
keeps hitting the cap a single failed attachment, shown with a reason on
the admin screen, rather than a dead pipeline run.

## Why the output is UTF-8 scrubbed here

`mutool` prints whatever the PDF's text decodes to, and a PDF submitted by
the public with a broken or mislabelled encoding produces bytes that are
not valid UTF-8 (see [Why Sway::Utf8.scrub exists](utf8-scrub-rationale.md)).
Nothing further down checked them, so they were written to a sidecar file,
saved into `extracted_testimony`, and eventually handed to a regular
expression in the positions prompt builder — which raised, outside the
rescue guarding that call, and marked an already-finished summary as
failed. Cleaning the bytes here, where they first enter the app, gives
every later step the same guarantee.
