---
mode: explanation
summary: "Explains why testimony text is rebuilt by re-reading sidecar files from disk on every run instead of kept in memory, plus a related type-checker crash."
status: agent-extracted
related: []
---
# Why testimony is composed from disk, not from memory

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService#persist_testimony!` writes
`BillLlmProvisioning#extracted_testimony` and `#testimony_attachments` for a
bill. This document explains why the extracted text is rebuilt by reading
files back off disk on every run, instead of being kept in memory during
the run, and records a type-checker crash this method used to trigger.

## The bug that composing from memory caused

`extracted_testimony` is built from the per-attachment `.txt` sidecar files
on disk, not from the current run's in-memory list of successful
extractions. Building it from memory quietly dropped attachments that had
worked on a previous run but failed on a re-fetch: run 1 captures
attachments A and B, run 2 loses B to a 404, and the stored column shrinks
down to A alone even though B's testimony was never actually retracted by
anyone.

The sidecar files are per-attachment and survive that kind of failure — they
live on the Kamal-mounted storage volume, independent of any single run's
success or failure. Rebuilding from them is therefore the right source of
truth. This rebuild is also the only place in the codebase that reads the
sidecars at all; before this fix, they were written and never read back.

## `testimony_fetched_at` only moves on a real change

`testimony_fetched_at` only updates when the composed text actually
changes. Re-running the fetch and getting the same result no longer marks
the summary stale for no reason.

## A removed parameter

The method used to take a third parameter, `_successful_texts`. It was
never read inside the method body, and it survived for a while only so
callers would not need to change when composition moved from
in-memory tracking to reading the disk sidecars — which is the opposite of
what a method signature is supposed to communicate. It has since been
removed.

## A type-checker crash that started here (fixed)

A `steep` crash used to originate in this method's type inference. `steep`
2.0.0 crashed one of its workers while working out this method's types,
which aborted type-checking for the WHOLE file — so a green "No type error
detected" result did not actually cover `fetch_hearings_service.rb` at all.
That has been fixed.

The cause was the `attachment_status` type alias, which was a record type
with STRING keys. `steep` raises on any record key that is not a `Symbol`,
and it fails with a bare `RuntimeError` that explains nothing about why. The
line inside `steep` itself that raises is not named here, because it lives
in a gem, not in this repository — a `steep` version bump could move it at
any time, so pinning a line number here would go stale silently.

RBS itself accepts string keys without complaint, which is why `rbs parse`
stayed clean the whole time and why the crash looked inexplicable from the
RBS side alone. The `attachment_status` alias is now a `Hash` type instead
of a string-keyed record. See the comment on it in
`sig/services/fetch_hearings_service.rbs` for the full account, and check
there first if this crash ever comes back.

## Why a "no text this run" attachment can still contribute text

`#extract_attachments!` treats every record's extraction outcome as
provisional until it also checks whether a `.txt` sidecar is actually
present on disk (`#attachment_txt_present?`). `#compose_testimony_from_disk`
reads every sidecar it can find, so an attachment that produced no text
THIS run but still has a `.txt` file on the storage volume from an earlier
run IS feeding that earlier text into `extracted_testimony`, and from there
into the positions prompt. That reuse is deliberate — see "The bug that
composing from memory caused" above — but it used to be invisible; the
extraction loop now says so out loud by flipping the record's status to
`EXTRACTION_STATUS_REUSED`.

## Why a failed sidecar write returns nil instead of reporting success

`#extract_one_attachment` rescues `SystemCallError`/`IOError` around the
`.txt` sidecar write and returns `nil` (leaving the record
`extraction_status: "extraction_failed"`) rather than returning the
extracted text, kept to this one attachment exactly like the PDF write.
The sidecar is what `#persist_testimony!` later composes the testimony
from, so a failed write must not be reported as a successful extraction —
text that was never actually saved to disk must not be treated as evidence
that reached the composition.

## Why `#attachment_txt_present?` asks the reader's own question, not a stand-in for it

`#attachment_txt_present?` used to just check `path.exist?` and lean on a
rule to bridge the gap: "`#extract_one_attachment` never writes a blank
sidecar (it returns early when the extracted text is all whitespace), so a
file that exists is text `#compose_testimony_from_disk` will keep." That
held for files THIS version of the code wrote, and not for a zero-byte or
whitespace-only file left by an older version, a half-finished write, or
something outside truncating it — and when it broke, the record was
flipped to `EXTRACTION_STATUS_REUSED` with an error reading "showing text
captured by a previous run" while the composition took nothing from it.

The fix asks the READER's own question directly instead of a stand-in for
it: the test inside `#attachment_txt_present?` is word for word
`#compose_testimony_from_disk`'s own skip condition, using the same reader
(`#read_attachment_txt`), so the two cannot drift apart again. A record
with no id, a missing file, and an unreadable file all come back as
"absent" from `#read_attachment_txt`, which is why `#attachment_txt_present?`
needs no checks of its own beyond calling it.

The cost is one extra size-limited read per skipped record (the read stops
at `MAX_ATTACHMENT_TEXT_CHARS * 4` bytes), paid only when extraction did
not succeed — cheaper than an operator re-pasting testimony that was never
actually missing.

## Why the reused-attachment error message is rewritten, not just the status

When a record's status flips to `reused_prior_run`, its `error` field is
rewritten too (`#reuse_error`), run AFTER `#extract_one_attachment` may
have already set both a failed status (`extraction_failed`) and an error
explaining that failure. Without the rewrite, the admin list showed a row
reading `reused_prior_run` next to "extraction produced no text layer" —
not false, but self-contradictory on the one screen an operator uses to
decide whether to paste testimony by hand. `#reuse_error` folds both facts
into one sentence instead of dropping either: "this run could not
re-extract (`<reason>`); showing text captured by a previous run."

## Why `#persist_testimony!` always rewrites `testimony_attachments`

`#persist_testimony!` creates the row if the bill has none yet (the same
`bill.bill_llm_provisioning || bill.build_bill_llm_provisioning` pattern
`GenerateDiffsService#persist_diff_artifact!` uses). `testimony_attachments`
is ALWAYS rewritten — the admin needs to see this run's per-attachment
failures even when nothing was captured.

## Why `#extract_attachments!` is where the single extraction retry lives

The single retry lives HERE, in the caller — `TestimonyTextExtractor#call`
deliberately makes exactly one mutool attempt per call. The extracted text
is written to that attachment's `.txt` sidecar and is NOT stored back onto
the record; only the short status summary is.
