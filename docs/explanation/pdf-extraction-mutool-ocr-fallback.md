---
mode: explanation
summary: "Explains why bill PDF text extraction tries mutool's native text layer first, only falls back to OCR when needed, and the safety rules behind that design."
status: agent-extracted
related: [docs/explanation/mupdf-preflight-tessdata-check.md, docs/explanation/mupdf-ocr-unavailable-detection.md, docs/explanation/mupdf-ocr-unavailable-memoization.md, docs/explanation/mupdf-empty-ocr-text-guard.md, docs/explanation/mupdf-ocr-page-cap.md, docs/explanation/mupdf-ocr-workspace-error-handling.md, docs/explanation/mupdf-output-scrubbing-and-timeouts.md]
---
# Why MupdfExtractor tries native text first and falls back to OCR

<!-- vale Vale.Spelling = NO -->

`MupdfExtractor` pulls the text out of a bill PDF. It replaced the old
Python extraction script (`pymupdf4llm` + `pytesseract`) that used to live
in `legislation/extract_text.py`.

It runs the `mutool draw` command-line tool through
`Sway::Subprocess.capture3`. It tries the cheap path first, and only falls
back to OCR (optical character recognition — turning a picture of text
back into text) when it has to. An exploratory spike validated this
design; the write-up is at
`.claude/skills/spike-findings-sway/references/pdf-extraction.md`.

## The extraction rules

1. Try `mutool draw -F txt` first. If it returns at least `MIN_NATIVE_CHARS`
   characters, use that text and skip OCR entirely. About 85% of bills
   carry a real text layer, so this cheap path wins most of the time.
2. Otherwise, run `mutool draw -F ocr.txt -r 300`. This uses the Tesseract
   OCR engine bundled inside `mutool`, at 300 DPI. The default 96 DPI
   destroys word boundaries — output looks like `CityOFBALTIMORE`.
3. Some Linux packages ship `mutool` without its bundled OCR (Debian
   trixie's `mupdf-tools` package is built with `HAVE_LEPTONICA=no
   HAVE_TESSERACT=no`). When that happens, step 2 writes "OCR Disabled in
   this build" to stderr. `MupdfExtractor` detects that message once per
   worker process, then falls back to rendering each page with `mutool`
   and running the separate `tesseract` binary on it. Before this fallback
   existed, every image-only bill failed, until the pipeline's failure
   budget aborted the whole run.
4. The `TESSDATA_PREFIX` environment variable must be set. If it is not,
   `mutool`'s OCR mode silently returns empty output with a successful
   exit status — a failure nothing can detect after the fact. So
   `MupdfExtractor` raises `MissingTessdataError` up front, at
   construction time.
5. `Sway::Subprocess.capture3` always gets its arguments as separate
   values (`"mutool", "draw", ..., path`), never as one shell-interpolated
   string. No shell ever runs, so a malicious PDF file name can never
   inject shell commands.

## Why this is a service class

A subprocess is the right tool here — the `ksylvest/mupdf` gem does not
expose OCR. Callers still use `MupdfExtractor.new(path).call`, never a raw
subprocess call, and the subprocess itself goes through
`Sway::Subprocess`, which wraps `Open3.popen3` with a hard time limit.

## Related decisions

Each of these covers one design choice inside `MupdfExtractor` in more
depth:

- [Why the tessdata preflight check runs as a class method](mupdf-preflight-tessdata-check.md)
- [Why `OcrUnavailable` is a separate exception class](mupdf-ocr-unavailable-detection.md)
- [Why the "OCR unavailable" memo is keyed off the exception's class](mupdf-ocr-unavailable-memoization.md)
- [Why OCR output must never be empty](mupdf-empty-ocr-text-guard.md)
- [Why `MAX_OCR_PAGES` caps the OCR fallback](mupdf-ocr-page-cap.md)
- [Why a temp-directory failure must not abort the whole pipeline run](mupdf-ocr-workspace-error-handling.md)
- [Why mutool's output is scrubbed for invalid UTF-8 and time-limited](mupdf-output-scrubbing-and-timeouts.md)

## How the two threshold constants were chosen

`MIN_NATIVE_CHARS` (50) is the threshold the spike validated: in practice it
separates "real text layer" from "an image-only PDF that carries a title
page's worth of stray text". Fewer characters than that from the native
text path routes the PDF into OCR instead of trusting a near-empty native
result.

`OCR_DPI` (300) is the minimum the spike found at which Tesseract reliably
recovers word boundaries — 72 or 96 DPI produce garbage
(`CityOFBALTIMORE`, lost characters).

## How the standalone-tesseract fallback is implemented

When mutool's bundled OCR is unavailable, `#ocr_via_tesseract` renders each
PDF page to a 300 DPI PNG via `mutool draw -F png` — rendering to images
works even when `mutool` was compiled without OCR — then runs
`tesseract <png> stdout -l eng` on each page and joins the results with a
blank line between pages, the same shape as `mutool`'s own `ocr.txt`
output.
