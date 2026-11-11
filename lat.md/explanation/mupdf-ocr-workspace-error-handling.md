---
lat:
  mode: explanation
---

# Why a temp-directory failure must not abort the whole pipeline run

`Dir.mktmpdir` can itself raise a `SystemCallError` — for example, a full or read-only `/tmp` (`ENOSPC`/`EACCES`), a live concern on the single production Raspberry Pi.

## Why it must become ExtractionFailed

That failure is a per-bill condition, and it has to be raised as one.

The only structured error types `MupdfExtractor`'s caller knows about are `ExtractionFailed` and `MissingTessdataError`. A bare `Errno::` exception would instead reach the pipeline job's catch-all and become a `StageError`, which aborts text extraction for every remaining bill — not just the one that hit the problem.

## Why the message names the workspace, not a binary

`#run_png_render` and `#run_tesseract` each translate their own errors before they can reach this rescue clause, so whatever does reach it came from the workspace itself, not from a subprocess.

`#run_png_render` and `#run_tesseract` each translate their own errors before they can reach this rescue clause, so whatever does reach it came from the workspace itself, not from a subprocess — which is why the resulting message names the workspace rather than a binary.
