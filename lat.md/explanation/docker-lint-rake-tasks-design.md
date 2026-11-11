---
lat:
  mode: explanation
---

# Why docker_lint_spec.rb tests three rake tasks the way it does

Why spec/lib/tasks/docker_lint_spec.rb exists and how it tests the docker:lint:tessdata_parity, docker:lint:sqlite_flags, and docker:lint:sqlite_runtime rake tasks.

## docker:lint:tessdata_parity

This task checks that `.dockerdev/Dockerfile` and `ops/pdf-extractor/Dockerfile` install the same Tesseract OCR language packs, and that `production.alpine.dockerfile` installs no PDF extraction tools.

It shipped without any tests — its sibling, the legislation lint task, arrived with both matching and non-matching cases for its pattern; this one did not.

`spec/lib/tasks/docker_lint_spec.rb` closes that gap by calling `extract_tesseract_langs` directly — strings that should match, strings that should not, several packages on one line, and lines continued with a backslash — plus the comparison between the two dockerfiles, where a difference aborts and a match passes.

The extractor is checked purely on what its pattern matches. The comparison between dockerfiles is driven by inline fixture strings, so that half of the test does not depend on what the shipped dockerfiles happen to contain right now. A separate "shipped dockerfiles" smoke test reads `.dockerdev/Dockerfile` and `ops/pdf-extractor/Dockerfile` directly, and verifies that non-comment lines in `docker/dockerfiles/production.alpine.dockerfile` omit `mupdf-tools`, `tesseract-ocr`, and `TESSDATA_PREFIX` — if they drift apart or PDF packages return to the Rails image, both the CI rake task and this spec fail with a readable difference.

The helper lives in a named module, `DockerLintHelpers`, inside the rake namespace, so it can be called directly instead of `eval`-ing a chunk of the rake source. The rake file is loaded once as the spec file loads, so the module exists before any example runs. The examples refer to `DockerLintSpecHelpers`, an alias set up right after the rake task loads.

## docker:lint:sqlite_flags

The sibling task, `docker:lint:sqlite_flags`, keeps the SQLite build options identical across both dockerfiles and refuses two options outright.

The extractor is tested on what its pattern matches, the same way the tesseract one is. The two forbidden options each get their own example, because a gate that never bites is worse than no gate: it prints success while guarding nothing.

`docker/dockerfiles/local.dockerfile` was deleted: its final stage was commented out, so it produced no image, and the only thing reading it was the tessdata lint — which therefore compared production against a file nobody built. The spec pins that the shipped-dockerfile list never includes it again; if it ever comes back, it must not be what a lint treats as the Debian side.

## docker:lint:sqlite_runtime

The sibling tasks read dockerfiles.

This one reads the SQLite that is actually loaded at runtime, and it exists because CI compiles gems on the host rather than through any dockerfile — so an agreeing set of dockerfiles said nothing about what CI itself links against.

Every example drives `sqlite_runtime_problems` with an option set given by hand, rather than reading the real `PRAGMA compile_options` from the process running the spec. That keeps the examples honest on a machine whose own sqlite3 was built any which way, and it lets a broken state be reproduced exactly rather than only on a machine that happens to already be broken.
