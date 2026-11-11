---
mode: explanation
summary: "Explains GenerateDiffsService's Python-parity contract end to end: the non-amending-bill zero-result path, disk-then-DB artifact persistence, the N+1 fix in build_section_payloads, and the matching Python-parity rules in ApplyOperations, MarkdownRenderer, and DiffRenderer."
status: agent-extracted
related: [docs/reference/bill-amendment-operation-column-contract.md, docs/explanation/pipeline-artifact-presence-overview.md]
---
<!-- vale Vale.Spelling = NO -->

# GenerateDiffsService design notes

`GenerateDiffsService` shows what a bill would change in the law: current
law text vs. that text with the bill's amendment operations applied. It is
a faithful Ruby port of an older Python script. For each
`bill_section_reference` on the bill: look up `target_law_section.body` as
`before_text`; run the section's `BillAmendmentOperation`s over it with
`ApplyOperations` to get `after_text` plus any warnings; hand both texts to
`DiffRenderer.make_diff_block`; build a `DiffResult` JSON payload and a
Markdown payload, both in the same shape the Python version produced; and
write both to disk at `legislation/diffs/<bill.external_id>.{json,md}`.

The diff always means "the law before" vs "the law after applying the
bill's operations". There is no "previous bill version" anywhere — the old
idea of diffing bill version 1 against version 2 is gone.

## Why a non-amending bill gets a zero-result, not a raised error

A bill with no section references AND no amendment operations is a
NON-AMENDING bill (a resolution, an appointment, a building naming, etc.)
— not a parse failure. The Python pipeline wrote an empty diff artifact
for these bills; raising `BillProcessingError` here would trip the
stage-budget guardrail after 5 consecutive non-amending bills and
force-fail the entire run. `#call` returns a zero-result instead, so the
orchestrator marks the per-bill row succeeded with `sections_modified=0`
and the run continues.

It also saves a placeholder, empty `diff_content` for these bills, so
`Pipeline::ArtifactPresence.generate_diffs?` reports `present` for every
bill the stage ran on, not only the ones with sections — see [Pipeline::ArtifactPresence
overview](pipeline-artifact-presence-overview.md) for the general shape of
that "did this stage conclude, not does an artifact exist" question.

`#empty_sentinel_payload` gives that placeholder the SAME shape as the JSON
written for amending bills, so everything downstream only ever has one
shape to parse: `sections` is an empty array and every count is 0.

## Why generated_at is built the way it is

Python emits a microsecond-precision UTC timestamp ending in `+00:00`.
`Time#iso8601(6).sub(/Z\z/, "+00:00")` produces the exact same bytes as
Python's `datetime.now(timezone.utc).isoformat()`.

## Why summary is always null here

This stage never fills in `summary` — summarizing is a separate stage. The
Python pipeline also emitted null here before summarize ran.

## Why the artifact is written to disk before the DB record

`persist_diff_artifact!` mirrors the on-disk JSON into
`bill_llm_provisioning.diff_content` so `Pipeline::ArtifactPresence`, the
alerting and auto-include logic built on it, and the downstream UI
(`BillCreatorLlmSummary`, `bills_controller#edit`) all see the same
canonical artifact state. Disk is written first: the artifact files must be
safely written before the DB records that they exist; if the DB write
fails, the files remain and the next run reconciles.

Existing `bill_llm_provisioning` rows (e.g. carrying `llm_summary` from a
prior summarize run) are preserved — only the `diff_*` columns are
touched.

## Why lookup_law_section never crosses locales

`#lookup_law_section` finds the `LawSection` a reference points at, the
same way the Python original's `section_index.get(sec_ref.key)` lookup
did. A reference whose resolution is `:unresolved` returns nil right away;
otherwise the `LawSection` is fetched by key, always within the bill's own
locale and never across locales. In production the pipeline's law stage
fills in the `LawSection` rows; tests build them directly with FactoryBot.

## Why build_section_payloads loads all operations in one query

`#build_section_payloads` loads ALL of the bill's amendment operations in
one query, grouped by `bill_section_reference_id` — the previous shape ran
one query per reference (an N+1). The explicit `order(:ordinal)` repeats
what `BillAmendmentOperation`'s default_scope already does; it is a
defensive re-sort in case `.unscoped` ever enters the chain.

## Why bill-level operations are counted but never rendered as a section

The text-pattern fallback parser writes bill-level operations
(`bill_section_reference_id` NULL) when it cannot tell which section an
operation belongs to. The Python pipeline counted these but rendered no
per-section diff blocks for them. `#build_section_payloads` matches that:
they add to `total_operations`, but emit no extra section.

## ResultWriter: why a disk failure becomes BillProcessingError, not a run-killing error

`GenerateDiffsService::ResultWriter` puts the service's output on disk at
`legislation/diffs/<external_id>.{json,md}`, or wherever
`ENV["LEGISLATION_DIFFS_ROOT"]` points instead — specs aim it at a
temporary directory so test runs leave no mess in a developer's
workspace.

Both `write_json` and `write_markdown` turn a disk failure into
`BillProcessingError`, the class the pipeline's per-bill failure budget
knows how to handle. A full disk, a read-only mount, or too many open
files raises a `SystemCallError`, which is not a `BillProcessingError`, so
the orchestrator's catch-all would turn it into a run-killing `StageError`
— one bad write costing every remaining bill in the run.
`FetchHearingsService`'s artifact write was hardened this way earlier;
these are its siblings.

Both writers get their path from `Legislation::Paths`, which turns the
external_id into one safe piece of a file path. These are two of the
write sites that mattered when that check was added, and the diffs
directory is also what `BillSummaryPromptBuilder` reads back later.

## ResultWriter: why write_markdown checks the type of body before writing

`write_markdown` is the Markdown twin of `write_json` and writes the body
to disk exactly as given. If a Hash ever slipped through — easy to do
during a refactor — `Pathname#write` would quietly call `to_s` on it and
leave `{:foo=>"bar"}` in the file, which is baffling when regenerating the
reference output this port is compared against. It raises `ArgumentError`
instead.

## ApplyOperations: the Python-parity contract

`GenerateDiffsService::ApplyOperations` applies a bill's amendment
operations (strike, insert, replace) to the text of a law section. This is
a line-for-line port of the older Python version, and it has to keep
producing the exact same output.

Two Ruby details keep it exact:

- Python's `str.replace(old, new, 1)` changes only the first match. Ruby's
  `String#sub` does the same. `gsub` (changes every match) or `sub!`
  (edits the string in place) are NOT used. `String#sub` hands back a new
  String, which is why the caller starts from `after = before_text.dup`.
- Every `#sub` call uses the BLOCK form (`after.sub(anchor) { "" }`), not
  the two-argument form. With the two-argument form, Ruby reads `\&`, `\1`
  and `\0` in the replacement text as references back to the match.
  Python's `str.replace` does no such thing — it inserts the replacement
  characters exactly as given. The block form skips Ruby's
  replacement-string parsing entirely.
- Python's `if "X" in s` becomes Ruby's `s.include?("X")`.

An `:insert` operation always appends to the end, because the
text-pattern source gives no anchor to insert at — that is what the Python
version did too. Insert operations keep their new text in
`:replacement_text`, which is where `ParseSectionsService` puts it.

A `:replace` operation rebuilds the single flat string Python worked with
out of the two database columns this port split it into. When the
text-pattern parser was the source, `anchor_text` holds everything and
`replacement_text` is empty, so the rebuilt string has no `" -> "`
separator and a warning fires — same as Python did. See [BillAmendmentOperation
column contract](../reference/bill-amendment-operation-column-contract.md)
for how those two columns get filled by the upstream parser.

Replace operations that came from the text-pattern parser look broken on
purpose. Do not "fix" that: the saved reference output from the old Python
pipeline carries the same warning, and this port has to keep matching it.

## MarkdownRenderer: the Python-parity contract

`GenerateDiffsService::MarkdownRenderer` turns a `DiffResult` into
Markdown. This is a line-for-line port of an older Python script, kept
identical so the output of the two can be compared. The Ruby orchestrator
passes extra per-section keys (`_diff_block`, `_warnings`, `_before_text`,
`_resolution`, `_status`) along in the payload, so this renderer can pick
the right branch in `#render_section` without working the state out again
from the database rows.

## MarkdownRenderer: why sections are grouped by article

`#content_parts` groups the sections by article name. Without the
grouping, two references in a row that point at the same article would
each print their own H2 heading. Sections whose status is
`"section_not_found"` are gathered under one stand-in heading, "Unresolved
References".

## DiffRenderer: why the unified diff is built by hand

`GenerateDiffsService::DiffRenderer` builds the body of a unified diff —
the familiar "-old line / +new line" listing — one line at a time, by
hand, because the `diff-lcs` gem has no `unified_diff` method.

The older Python version of this code called `difflib` for the whole diff
and then threw away the `---`/`+++`/`@@` header lines; this port goes
straight to the content lines instead, so the two produce the same text.
`Diff::LCS.sdiff` hands back `ContextChange` objects, each carrying one of
these action symbols:

- `"="` equal → emit `" <line>"` (space-prefixed; matches difflib context)
- `"-"` delete → emit `"-<line>"`
- `"+"` insert → emit `"+<line>"`
- `"!"` replace → emit `"-<old>"` then `"+<new>"` on adjacent lines
  (Python has no `"!"`; difflib decomposes a change into a delete/insert
  pair — this mirrors that decomposition)

## DiffRenderer: why line endings must not be re-split

`String#lines` keeps the trailing `"\n"` on each line, which is what the
Python version did too. Splitting on a literal newline instead would drop
the trailing newline, and the output would stop matching the Python
baseline character for character.

## DiffRenderer: why an all-context diff renders as no diff at all

The Python version had the same guard: if every line produced is an
unchanged context line — one of the space-prefixed ones — then nothing
actually differs and there is no diff to show, so `#make_diff_block`
returns `""`.
