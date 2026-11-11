---
lat:
  mode: explanation
---

# Why FetchLawCorpusService exists, and how it stays safe on a single-Pi deploy

Why FetchLawCorpusService exists, the download algorithm it mirrors from the old Python script, its offline fallback, and why its byte caps are sized the way they are.

## Why this service exists

`FetchLawService` only PARSES `law/raw/**/charter.xml` — it does not download it.

When the pipeline moved from Python to Ruby, the download step was lost: dev machines happened to still have the corpus on disk, but production's fresh volume did not, so the first run failed with `StageError: missing charter.xml`. This service restores that download step.

## The algorithm it mirrors

It mirrors the download half of the old Python script (`legislation/.archive/fetch_law.py`):

1. Ask the GitHub API for the law-xml repo's latest commit SHA.
2. Skip the download when the saved `.commit_sha` matches AND `charter.xml`
   is already on disk — so it only re-downloads when upstream changed.
3. Otherwise download the `main.tar.gz` archive and extract it into
   `<law_root>/raw/`.
4. Save the new SHA to `.commit_sha` for the next run's check.

Extraction uses only Ruby's standard library (gzip + tar) — no rubyzip dependency and no shelling out.

`#extract_tarball` extracts the gzipped tarball into `raw_root` using only the standard library. It matches the Python original's `zf.extractall(raw_dir)`. Entries that would land outside `raw_root` (absolute paths, or `..` climbing out of the directory) are skipped.

## Offline tolerance

If GitHub is unreachable but a corpus already sits on disk, the service logs a warning and carries on with the cached copy.

The only fatal case is "no corpus on disk AND the download failed" — that raises `StageError`, which the pipeline job (`RunLegislationPipelineJob#run_run_level_stage`) treats as a whole-run failure via `handle_run_failure`, not a single-bill failure.

## Why the byte caps are sized the way they are

Every other download path added in this phase — `ExternalAssetMirrorService`, `Legistar::AttachmentFetch` — caps both the bytes read over the network and what gets written to disk.

This service used to read a tarball fully into memory and gzip-expand it with no bound on either number, which on the single Raspberry Pi that runs production means a large or hostile archive could exhaust memory and take the whole site down.

The real corpus is about 32 MB extracted (`legislation/law/raw/`). `MAX_TARBALL_BYTES` (64 MB compressed) and `MAX_EXTRACTED_BYTES` (256 MB extracted) follow `AttachmentFetch`'s approach — roomy enough that the real corpus growing over time is not refused, tight enough that a hostile or broken upstream cannot exhaust the Pi's memory.

## Why REQUIRED_CORPUS_FILE is charter.xml

`charter.xml` (`FetchLawService::CHARTER_FILE`) is the one file the corpus must contain.

Finding it on disk after extraction is how `#corpus_present?` knows the download and extract actually worked, rather than leaving silent partial state behind.

## Why REPO and BRANCH are read with EnvSecret.read + ||, not ENV.fetch

`ENV.fetch(name, default)` only falls back when the variable is completely unset — a variable set to `""` or `"main\n"` passes straight through.

Both `repo` and `branch` are interpolated into `commits_url` and `tarball_url`, where a stray newline gets percent-encoded and the request 404s. `GitHubPrService` had the same bug.

## Why download_tarball reads a chunk at a time, not response.body

`#download_tarball` reads a chunk at a time, so an oversized archive is refused rather than held, following THE SAME SHAPE AS THE ATTACHMENT DOWNLOAD.

`#download_tarball` reads a chunk at a time, so an oversized archive is refused rather than held, following THE SAME SHAPE AS THE ATTACHMENT DOWNLOAD — and it was left with the same fault when that one was fixed: the cap was measured on `resp.body`, which Faraday has already read into memory in full. On a machine with 8 GB and a 64 MB cap, a broken or hostile upstream could hand over as much as it liked and the check would describe a string already paid for. `BoundedResponseBody` stops the read instead.

This connection mounts `follow_redirects` (github.com sends the archive on to codeload), so the hop's own body streams through here too. `keep:` drops it: a redirect page is not the archive, and the middleware re-reads from the target, which the running total would otherwise count as a fresh attempt.

## Why MAX_EXTRACTED_BYTES is a separate cap from MAX_TARBALL_BYTES

`#extract_tarball` raises `TooLarge` as soon as the running total of entry sizes (declared in each tar header, checked before that entry is read into memory) passes `MAX_EXTRACTED_BYTES`.

A gzip bomb can be a tiny download that expands to gigabytes, so the compressed-size cap in `#download_tarball` does not cover this — the two caps guard different points on the same path.

## Why extract_tarball needs two narrow Steep suppressions

`#extract_tarball` carries two `# steep:ignore` comments for gaps in the standard-library type signatures, with the typed destination check living in `#safe_destination` instead:

- `GzipReader.wrap` is declared to take `::IO` — `StringIO` behaves like an
  IO at runtime but is not an `::IO` subtype in RBS.
- `rubygems` (`Gem::Package::TarReader`) ships no RBS signatures at all.

## Why unchanged? and persist_commit_sha both rescue SystemCallError/IOError

`#unchanged?` treats "cannot read the marker file" the same as "no marker file": re-download.

Raising here instead would bubble up to `RunLegislationPipelineJob`'s catch-all rescue and kill the whole run over what is only a cache hint. The file can also vanish between `exist?` and `read` (a check-then-use race), so the rescue is needed regardless.

`#persist_commit_sha` rescues the write half of the same marker-file guard. Whatever makes the marker unreadable there usually makes it unwritable here too, so guarding only the read would move the run-killing error a few lines down instead of removing it. By this point the corpus is already extracted and `#corpus_present?` runs next; a missing marker only costs a re-download on the following run — not worth failing a stage that otherwise succeeded.
