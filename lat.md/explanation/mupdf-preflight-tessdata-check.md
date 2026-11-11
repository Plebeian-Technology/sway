---
lat:
  mode: explanation
---

# Why the tessdata preflight check runs as a class method

`MupdfExtractor.preflight!` is a class-level environment check that runs before a legislation pipeline run starts.

## Why it moved out of the constructor

The pipeline orchestrator used to probe for `MissingTessdataError` by constructing `MupdfExtractor.new("/dev/null")`.

That trick only worked because the constructor never touched the file system. Exposing the check as the class method `self.preflight!` removes that hidden coupling — the probe no longer depends on the constructor's internals staying inert.

## Why it checks three separate conditions

`mutool`'s OCR mode silently produces empty stdout with a successful (zero) exit status in all three of these cases:

- `TESSDATA_PREFIX` is unset.
- The directory it points to does not exist.
- The directory exists but holds no `.traineddata` files.

The preflight check tests all three, once, before a local pipeline run starts. Catching the problem here replaced an older failure mode, where five bills would fail in a row, trip the pipeline's failure budget, and report a misleading error that did not point at the real cause. When `Sway::Settings.legislation.pdf_extractor_url` is present, `MupdfExtractor.preflight!` returns early without inspecting `TESSDATA_PREFIX` because PDF text extraction and OCR run on the host `ops/pdf-extractor` service rather than inside the Rails container.

## Why the glob is recursive

The `.traineddata` search uses a recursive glob (`File.join(tessdata.

The `.traineddata` search uses a recursive glob (`File.join(tessdata, "**/*.traineddata")`) so it handles both the common Alpine layout (`/usr/share/tessdata/eng.traineddata`) and the macOS Homebrew layout (`/opt/homebrew/share/tessdata/4.x.x/eng.traineddata`). `**/` matches ZERO or more directories, so this one glob already finds `<tessdata>/eng.traineddata`. A non-recursive glob used to sit in front of it as an `||`, which could never decide anything the recursive one did not.

## Why the eager preflight! call at construction time is a documented test seam

`self.class.preflight!` runs eagerly inside `#initialize` so a misconfigured worker fails fast instead of quietly producing empty extractions.

RSpec callers that stub `MupdfExtractor.preflight!` to a no-op (to bypass ENV in CI) also bypass this per-construction check — that is intentional, not a gap the tests happen to leave open.
