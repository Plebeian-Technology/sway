---
lat:
  mode: explanation
---

# Why MupdfExtractor tries native text first and falls back to OCR

`MupdfExtractor` pulls the text out of a bill PDF. It replaced the old Python extraction script (`pymupdf4llm` + `pytesseract`) that used to live in `legislation/extract_text.py`.

It runs the `mutool draw` command-line tool through `Sway::Subprocess.capture3`. It tries the cheap path first, and only falls back to OCR (optical character recognition — turning a picture of text back into text) when it has to. An exploratory spike validated this design; the write-up is at `.claude/skills/spike-findings-sway/references/pdf-extraction.md`.

## The extraction rules

Heuristics determining when cheap native text extraction via `mutool draw` suffices and when fallback to OCR is required.

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

A subprocess is the right tool here — the `ksylvest/mupdf` gem does not expose OCR.

Callers still use `MupdfExtractor.new(path).call`, never a raw subprocess call, and the subprocess itself goes through `Sway::Subprocess`, which wraps `Open3.popen3` with a hard time limit.

## Related decisions

Each of these covers one design choice inside `MupdfExtractor` in more depth:

- [[docs/explanation/mupdf-preflight-tessdata-check.md|Why the tessdata preflight check runs as a class method]]
- [[docs/explanation/mupdf-ocr-unavailable-detection.md|Why `OcrUnavailable` is a separate exception class]]
- [[docs/explanation/mupdf-ocr-unavailable-memoization.md|Why the "OCR unavailable" memo is keyed off the exception's class]]
- [[docs/explanation/mupdf-empty-ocr-text-guard.md|Why OCR output must never be empty]]
- [[docs/explanation/mupdf-ocr-page-cap.md|Why `MAX_OCR_PAGES` caps the OCR fallback]]
- [[docs/explanation/mupdf-ocr-workspace-error-handling.md|Why a temp-directory failure must not abort the whole pipeline run]]
- [[docs/explanation/mupdf-output-scrubbing-and-timeouts.md|Why mutool's output is scrubbed for invalid UTF-8 and time-limited]]

## How the two threshold constants were chosen

`MIN_NATIVE_CHARS` (50) is the threshold the spike validated: in practice it separates "real text layer" from "an image-only PDF that carries a title page's worth of stray text".

Fewer characters than that from the native text path routes the PDF into OCR instead of trusting a near-empty native result.

`OCR_DPI` (300) is the minimum the spike found at which Tesseract reliably recovers word boundaries — 72 or 96 DPI produce garbage (`CityOFBALTIMORE`, lost characters).

## How the standalone-tesseract fallback is implemented

When mutool's bundled OCR is unavailable, `#ocr_via_tesseract` renders each PDF page to a 300 DPI PNG via `mutool draw -F png`.

When mutool's bundled OCR is unavailable, `#ocr_via_tesseract` renders each PDF page to a 300 DPI PNG via `mutool draw -F png` — rendering to images works even when `mutool` was compiled without OCR — then runs `tesseract <png> stdout -l eng` on each page and joins the results with a blank line between pages, the same shape as `mutool`'s own `ocr.txt` output.

## Optional remote extraction service

When `pdf_extractor_url` is configured in settings, [[app/services/mupdf_extractor.rb#MupdfExtractor#call]] offloads extraction over HTTP.

The standalone Go microservice in [[ops/pdf-extractor/main.go]] handles native text extraction and OCR fallback on the host or in a sidecar. Offloading removes heavy `mutool` and `tesseract` CPU and memory burdens from Rails application containers.

Requests pass `pdf_path`, `min_native_chars`, `ocr_dpi`, `max_ocr_pages`, and an optional `disable_ocr` flag as JSON to `/extract` (preserving any base URL path prefix). When `disable_ocr` is true (used by native-only callers such as [[app/services/testimony_text_extractor.rb#TestimonyTextExtractor]]), the service runs `mutool draw -F txt` and returns the raw stdout immediately — including an empty string when a PDF lacks a text layer — or returns HTTP 500 when `mutool` fails, without invoking OCR. When `disable_ocr` is false or omitted, successful responses return JSON containing extracted text and a truncation boolean; when truncated, [[app/services/mupdf_extractor.rb#MupdfExtractor]] appends `OCR_PAGE_TRUNCATION_NOTICE`. Any network error, timeout, HTTP failure status, or empty text result in `MupdfExtractor` raises `ExtractionFailed` with scrubbed text so callers receive clean errors. When `pdf_extractor_url` is nil, [[app/services/mupdf_extractor.rb#MupdfExtractor]] executes the local subprocess pipeline.

### Path validation and concurrency budgeting in the Go service

The Go microservice translates container storage paths, validates every requested file path against `PDF_EXTRACTOR_ALLOWED_ROOT`, and separates semaphore queue waiting from the per-extraction subprocess timeout.

Because the Rails container mounts storage at `/rails/storage` while the host service reads from the host directory in `PDF_EXTRACTOR_ALLOWED_ROOT`, `validatePDFPath` maps absolute paths under `PDF_EXTRACTOR_CONTAINER_ROOT` (default `/rails/storage`) into `PDF_EXTRACTOR_ALLOWED_ROOT` whenever the path is not already inside `PDF_EXTRACTOR_ALLOWED_ROOT`. Before invoking `mutool`, `validatePDFPath` enforces lexical boundaries, resolves symlinks on both the allowed root and the candidate path, confirms the target resides strictly inside the root directory, checks `fi.Mode().IsRegular()`, and requires a `.pdf` extension so arbitrary files or FIFO pipes cannot be read. Request handlers acquire the concurrency semaphore against the caller's request context before starting the 300-second execution timer, ensuring queued requests do not consume their OCR execution budget while waiting for a worker slot.

### Browser system spec supervision on loopback

The browser system spec in [[spec/system/admin/creator/pdf_extractor_microservice_spec.rb]] compiles and supervises the real Go binary on an ephemeral loopback port to exercise the Admin Bill Creator pipeline UI end-to-end.

Because the Docker test container mounts `/tmp` as a `noexec` `tmpfs` and defines `PORT=3000` in its environment, the spec compiles the binary into `Rails.root.join("tmp")` and overrides both `PORT` and `PDF_EXTRACTOR_PORT` when spawning the child process. Health checks poll `Process.waitpid2` alongside `/up` so an early process exit fails immediately rather than waiting out the deadline, and teardown sends `SIGTERM` with a bounded wait before escalating to `SIGKILL`. The Go module targets `go 1.22` in [[ops/pdf-extractor/go.mod]] so the standard `golang-go` package in the development image and RSpec CI workflow builds it without an external toolchain download.
