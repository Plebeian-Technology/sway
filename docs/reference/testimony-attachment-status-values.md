---
mode: reference
summary: "Catalogs every FetchHearingsService download_status and extraction_status value, and why each is distinct from its neighbors."
status: agent-extracted
related: []
---
# Testimony attachment status values

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService` writes a `download_status` and an `extraction_status`
onto every attachment record. This catalogs each value and why it is kept
distinct from its neighbors, rather than reused.

## `download_status`

| Value | Meaning |
| --- | --- |
| `pending` | Not yet attempted. |
| `failed` | Attempted and failed (bad id, non-2xx response, not a PDF, a Faraday error, a disk write failure). |
| `succeeded` | Downloaded and written to disk. |
| `not_attempted` | A synthetic value for a made-up mirror row (candidate truncation, retained-testimony notices) describing an attachment that was never discovered into the working set at all — distinct from `failed` because nothing was attempted. |
| `skipped_time_budget` | The per-bill download budget (`DOWNLOAD_BUDGET_SECONDS`) ran out before this attachment was reached. Not `failed`, because nothing failed — this attachment is work still to do, and the operator's next action differs from a dead attachment. |

## `extraction_status`

| Value | Meaning |
| --- | --- |
| `pending` | Not yet attempted this run — but see "Why `pending` cannot mean forever" below. |
| `succeeded` | Extracted and its `.txt` sidecar was written THIS run. |
| `extraction_failed` | Attempted this run and failed — mutool could not read a text layer, the write failed, or (see `docs/explanation/testimony-persistence-disk-composition.md`'s note) the classifier could not read the sidecar and its text is withheld. |
| `reused_prior_run` | Not written this run, but a sidecar from an earlier run is present and IS contributing text to the composed testimony. |
| `skipped_download_failed` | The download for this attachment failed, so extraction was never attempted — no sidecar exists. |
| `skipped_time_budget` | The per-bill extraction budget (`EXTRACTION_BUDGET_SECONDS`) ran out before this attachment was reached — distinct from `skipped_download_failed` for the same "work still to do" reason `download_status`'s equivalent value is distinct from `failed`. |
| `not_attempted` | Nothing was attempted and nothing failed — the extraction-side twin of `download_status`'s `not_attempted`, and shares its wording so a synthetic row reads the same on both axes instead of contradicting itself. It replaced `skipped_download_failed` at three sites where no download had actually failed: the two synthetic mirror rows, and every attachment the download budget never reached. |
| `content_denied` | The document was downloaded, extracted, and a language model read it and judged it not testimony. The record leaves the working set — its text must not reach `extracted_testimony` — but this status and its mirror row are what let an admin see the denial and its reason, rather than the document simply vanishing. |

## Why `pending` cannot mean forever

`#extract_attachments!` skips every record whose download did not succeed.
Before `skipped_download_failed` and `skipped_time_budget` existed, a
skipped record stayed at `extraction_status: "pending"` forever — a lie,
because nothing about that record is pending; this run will never extract
it. That was worse than a cosmetic wrong label:
`#compose_testimony_from_disk` reads the `.txt` sidecar unconditionally, so
a record stuck at `pending` could silently feed the positions prompt with a
PRIOR run's text while the admin mirror showed it as not-yet-done.

## Contributing vs. non-contributing statuses

`CONTRIBUTING_EXTRACTION_STATUSES` is `["succeeded", "reused_prior_run"]` —
the two values that mean "this attachment's text reached
`extracted_testimony`". This mapping is a fact about `#extract_attachments!`,
not an opinion re-derived at each comparison site: that loop leaves a
record `succeeded` only after writing a non-blank sidecar
(`#extract_one_attachment`), and flips every OTHER record to
`reused_prior_run` exactly when `#attachment_txt_present?` — which is
word-for-word `#compose_testimony_from_disk`'s own skip condition — says a
sidecar will contribute. The five remaining values (`pending`,
`extraction_failed`, `skipped_download_failed`, `skipped_time_budget`,
`not_attempted`) are precisely the records with no contributing sidecar.

See `docs/explanation/testimony-mirror-rule.md` for how this list is used
to detect evidence withdrawal across runs.
