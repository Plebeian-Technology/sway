---
mode: explanation
summary: "Explains the history and design of the three-stage service that fetches hearing metadata and testimony for a bill from Legistar."
status: agent-extracted
related: []
---

# Hearing fetch pipeline

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService` fetches hearing data and public testimony for one
bill from Legistar, Baltimore's legislative-data API. This document explains
why the service is shaped the way it is: its history, the mistakes each
stage's design corrects, and a hard constraint on which text extractor it
may use.

## Why a Ruby service, not the old Python script

This class is the Ruby replacement for an earlier Python script
(`legislation/fetch_hearings.py`) that did the same job. Its JSON output was
originally kept byte-identical to that script's output, so a rake task could
compare the two during the migration.

## A correction to an earlier version of this documentation

An earlier version of this service's header comment claimed the service
handled hearing-event metadata only, with attachment text extracted
elsewhere in the pipeline. That was wrong: the other pass that supposedly
did the extraction only ever looked at the bill's own PDF, so no attachment
text was ever extracted anywhere. This class now owns the whole
job — hearing metadata, attachment discovery, download, extraction, and
persistence.

## How the three stages came to be shaped this way

`FetchHearingsService` is invoked once per `pipeline_run_bill` — a
BILL-LEVEL pipeline stage. A failure fails only that one bill: the service
raises `BillProcessingError`, never `StageError`, because `StageError` would
stop the whole pipeline run. It writes the per-bill artifact to
`legislation/hearings/<external_id>.json`.

Three stages run per bill, in this order, all inside `#call_discover`:

**1. Hearing-event metadata.** `Matters/<id>/Histories` gives the hearing
`EventId`s (via `MatterHistoryEventId`), then `Events/<id>` is fetched per
event and mapped through `#event_to_hearing_hash`. This is what the method
returns.

An earlier version of this stage asked `Matters/<id>/Events` — which is
not a real Legistar endpoint. Because of that, the stage returned `[]` for
every single bill from the day it shipped. The endpoint name
was wrong from the start; nothing about the surrounding logic was.

**2. Testimony attachments.** `#discover_attachments` finds candidates from
both Legistar attachment collections, deduplicates them, keeps only `.pdf`
files, and pre-filters them with
`Testimony::AttachmentClassifier#prefilter`. Then `#download_attachments!`
saves the bytes to `Legislation::Paths.attachment_dir/attachment-<id>.pdf`.
Then `#extract_attachments!` writes the text to a `.txt` sidecar file next
to the PDF. Then `#classify_attachment_contents!` produces the LLM verdict,
run over that extracted text. Every step isolates failures per attachment;
none of them can fail the whole bill.

The LLM verdict deliberately runs LAST, after extraction. It
used to sit inside `#discover_attachments` and judge the file's NAME before
any text existed — which cannot work, because a candidate only reaches that
classifier when its name was *not* decisive enough for the keyword filter to
resolve on its own. The keyword half of the filter still lives where it
always did, so a name that the keyword rules deny is still never
downloaded — only the ambiguous cases fall through to the LLM, and only
after there is text for it to read.

**3. Testimony persistence.** `#persist_testimony!` writes
`BillLlmProvisioning#extracted_testimony` (composed from the on-disk
sidecars — see `docs/explanation/testimony-persistence-disk-composition.md`)
and `#testimony_attachments` (the "mirror": the per-attachment status list
the admin UI shows).

## Why the matter-existence check gates on an empty event collection

THE EVIDENCE GATE. An empty collection is only allowed to become an
authoritative "no hearings, no testimony" artifact once the matter is known
to exist upstream. It sits BEFORE `#discover_attachments` so that
`Matters/<id>/Attachments` — which also answers `200 []` for a bogus id —
can never be reached with an unverified `matter_id` either.

## The shape of the per-bill artifact

The per-bill artifact at `legislation/hearings/<external_id>.json` is
`{events, attachments, attachment_discovery}` — not the bare event array it
once was. The `attachments` field is every candidate this run worked with,
each carrying its own outcome: the ones whose text composed successfully,
the ones whose download or extraction failed, and the ones stage 3 denied.
It is a record of everything the run touched, not a list of contributors —
read each entry's `extraction_status` for that, the same way the admin
mirror does.

## Why `#write_artifact` unions the working set with `@content_denied_records`

A denied record leaves the WORKING SET — that is what keeps its text out of
the composition — but not the record of what this run saw. Without this
union the only durable trace of a decision that REMOVES EVIDENCE is the
mirror, which the next run rewrites, and the artifact contradicts itself:
`attachment_discovery.recorded` counts the denied candidates while
`attachments` does not list them. `#attachment_status_mirror` unions the
same two arrays, so artifact and mirror describe one population.

## Standing constraint: never use `MupdfExtractor` for testimony

Testimony text extraction goes through `TestimonyTextExtractor` and NEVER
`MupdfExtractor`. This is a hard rule, not a preference, for two reasons:

- `MupdfExtractor`'s constructor calls `preflight!`, which raises
  `MissingTessdataError` when `TESSDATA_PREFIX` is unset — and it is unset
  on the small production host. Routing testimony through it would fail every
  single bill on the machine that actually runs this pipeline.
- `MupdfExtractor#call` automatically falls back to OCR when a PDF has
  fewer than `MIN_NATIVE_CHARS` of native text. That would add an OCR
  dependency to testimony extraction, and OCR is deliberately out of scope
  for this pipeline.

`TestimonyTextExtractor`'s own class docstring states this same constraint
from the other side, so the rule is visible no matter which class a reader
starts from.

## Why backfill locale-scopes its bill lookup

`#call_backfill_missing` looks bills up scoped to `run_locale_id` because
`external_id` is not unique on its own — the bills unique index is
`(external_id, sway_locale_id)`. An unscoped lookup used to return an
arbitrary row when two locales shared an `external_id`, and
`#persist_testimony!` would then write one jurisdiction's testimony onto
the other's bill.

## `:backfill_missing` is kept even though nothing calls it today

`FetchHearingsService#call` dispatches on `@mode`, and `:backfill_missing`
has no production caller: the orchestrator
(`run_legislation_pipeline_job.rb`) only passes `mode:` when constructing
the `:fetch_bills` service, and `fetch_hearings` is a BILL_LEVEL stage
always built with the bare `{bill:, bill_run:, run:}` hash, so `mode` stays
at its `:discover` default on every real call. It is kept rather than
deleted: unlike `FetchBillsService`'s `:backfill_missing` (which IS wired
to a stage mode), this one is dead only because nothing dispatches it yet,
not because the feature it implements is unwanted.

## `#call_backfill_missing`'s per-bill error isolation

`#call_backfill_missing` walks `run.pipeline_run_bills`, skips bills whose
per-bill `hearings.json` artifact is already on disk
(`Pipeline::ArtifactPresence.present?("fetch-hearings", bill:)`), and for
each remaining bill re-runs the discover-mode fetch on a fresh, bill-scoped
instance. Errors on individual bills surface as `BillProcessingError` — the
same contract discover mode uses — and it is the orchestrator's per-bill
failure budget (`CONSECUTIVE_FAILURE_BUDGET = 5`) that decides when repeated
failures abort the backfill, not this method.

## `#event_to_hearing_hash`: a dead type check, and why every field is coerced

`#event_to_hearing_hash` builds the fixed-shape Hash for the per-bill
artifact's `events` array. It used to start with
`return {} unless event.is_a?(Hash)`, which could never fire —
`#fetch_hearing_event` already returns
`event.is_a?(::Hash) ? event : nil` and the caller's `#filter_map` drops
the nils, so only Hashes reach this method. That branch was worse than
useless: it told the next reader that empty `{}` rows can appear in the
artifact's `events` array, which would be a real claim about the evidence
if it were true. The type check now lives at `#fetch_hearing_event`, and
the RBS signature says the argument is a Legistar event, so the type
checker enforces it instead.

The five field values used to be copied through untouched. Legistar hands
back loosely typed JSON — any value can be a scalar or an array of scalars
— so nothing actually made the artifact's `EventId` an Integer or its
`EventDate` a String except upstream behaving itself, even though the
record type and every reader assumed otherwise. `EventId` is coerced with
the same `#coerce_attachment_id` already used before it goes into an
`Events/<id>` URL: without the coercion here too, an id discovery would
have REJECTED as invalid could still be written into the artifact that
outlives the run. Coercing in both places is what keeps those two answers
from disagreeing. A malformed `EventDate`/`EventTime`/`EventLocation`/
`EventBodyName` records `nil` rather than a stringified stand-in
(`#legistar_string`), because these fields are shown to users as the
hearing's date, time, and location, and a made-up `"[1, 2]"` looks just as
real as a genuine value.

## Why an unexpected write failure becomes `BillProcessingError`

A full disk, a read-only mount, or too many open files raises
`SystemCallError` (or `IOError`) from `File.write`/`File.binwrite`, in
`#write_artifact`, `#download_attachments!`, and `#extract_one_attachment`.
None of those is a `BillProcessingError`, so left unrescued the
orchestrator's catch-all rescue would turn it into a run-killing
`StageError` — discarding the per-attachment failure records the run has
already built, which are exactly what an operator needs to diagnose a disk
problem. Each of these three sites rescues the write and re-raises as
`BillProcessingError` instead, scoped to the object the write actually
belongs to:

- `#write_artifact`'s write failure fails the whole BILL: the artifact
  belongs to the bill, its absence correctly makes
  `Pipeline::ArtifactPresence.present?` false, and the next run retries the
  bill.
- `#download_attachments!` and `#extract_one_attachment`'s write failures
  are kept to the ONE attachment being worked on — the record is marked
  failed with a length-limited reason and the loop moves on, so a bad disk
  write on one attachment cannot fail the bill or the run by itself.

## A fourth site: `ActiveRecord::ActiveRecordError` on the testimony save

`#persist_testimony!` rescues `ActiveRecord::ActiveRecordError` around
`provisioning.save!` and re-raises as `BillProcessingError`, the same
pattern as the three write-failure sites above but for a database write
rather than a file write. Unlike the per-attachment download/extraction
paths, a failed testimony save really IS a per-bill failure — the row
belongs to the bill — so it still raises, but as `BillProcessingError`,
which the orchestrator's per-bill failure budget handles, rather than as
the bare `ActiveRecord` error its catch-all rescue would turn into a
run-killing `StageError`. The realistic trigger is SQLite reporting the
database as busy while another process is writing.

## Two per-bill time budgets, and why they are start-by deadlines

`DOWNLOAD_BUDGET_SECONDS` (15 minutes) and `EXTRACTION_BUDGET_SECONDS` (30
minutes) each bound one loop over a bill's attachment candidates —
downloading, then extracting. Both loops process up to
`MAX_ATTACHMENT_CANDIDATES` (200) attachments one after another with no
job-level watchdog above them (`RunLegislationPipelineJob` has none), so
without a budget, one blackholed attachment could occupy a Solid Queue
worker indefinitely: `Sway::Subprocess` bounds a single extraction call at
`DEFAULT_TIMEOUT_SECONDS` (300) plus a TERM grace, `#attempt_extraction`
retries once, and 200 attachments in sequence gives a ~34-hour worst case
for extraction alone. `Legistar::AttachmentFetch` issues up to
`MAX_REDIRECTS + 1 = 4` sequential GETs per attachment, and
`Sway::FaradayStack.legistar` retries each up to 4 times at a 30s timeout
with 0.5/1/2s backoff, so one stalled download costs ~123.5s per hop and
~494s total — ~27 hours for 200 attachments. Converting "hangs forever" into
"hangs for a day and a half" is still an outage on a single-worker Solid
Queue.

30 minutes for extraction is deliberately generous: twice
`GenerateBillSummaryJob`'s ~20-minute retry envelope, this codebase's
existing statement of how long one bill may reasonably occupy a worker.
Native text extraction is sub-second per attachment, so only a pile of
scanned documents can approach the budget — and when it is hit, the
remaining attachments are recorded (`EXTRACTION_STATUS_SKIPPED_BUDGET`)
rather than silently dropped, so the admin mirror tells the operator there
is work left to do. 15 minutes for download is shorter because that bound
is on TRANSPORT, where a stall is always pathological, whereas extraction
can legitimately spend minutes on a pile of scanned documents.

Both budgets are checked BEFORE each work item — a start-by deadline, not a
wall-clock ceiling — so each can be exceeded by up to one item's worst
case: extraction by up to ~610s (two `TestimonyTextExtractor` calls at
300s + 5s TERM grace each), download by up to ~494s (the redirect-and-retry
arithmetic above). One bill's true ceiling is therefore ~45 + ~18 =~ 63
minutes, not 45. That overshoot is bounded and known, which is why it is
accepted rather than engineered away: threading the remaining budget into
`Sway::Subprocess.capture3` (`timeout_seconds: [remaining, 300].min`) would make the
bound exact, at the cost of a per-call timeout that varies with position in
the loop — a worse failure to reason about when a single extraction times
out for no reason the operator can see.

Each loop reads a monotonic clock (`Process::CLOCK_MONOTONIC`) once at the
start and compares against it before each item, rather than a system clock,
so a clock change during the run cannot skew the deadline.

`*_STATUS_SKIPPED_BUDGET` is a distinct status from `*_STATUS_FAILED` /
`*_STATUS_SKIPPED` on both axes: nothing about the attachment failed, the
budget just ran out before it was reached, and the operator's next action
differs — a failed attachment is dead, a budget-skipped one is work still
to do. See `docs/reference/testimony-attachment-status-values.md` for the
full status vocabulary.

## See also

- `docs/explanation/testimony-write-decision.md` — how stage 3 decides what
  it is entitled to write.
- `docs/explanation/bill-text-filter-history.md` — why attachment
  discovery does not use a `primary: true` flag to reject bill text.
- `docs/reference/testimony-attachment-status-values.md` — the full
  download/extraction status vocabulary.
