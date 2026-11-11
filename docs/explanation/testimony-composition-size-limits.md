---
mode: explanation
summary: "Explains why testimony composition caps memory use while reading sidecar files from disk, not just the size of the final stored text column, and why the per-attachment and per-bill caps for testimony documents were raised together."
status: agent-extracted
related: []
---
# Why testimony composition bounds memory, not just the final column

<!-- vale Vale.Spelling = NO -->

`FetchHearingsService#compose_testimony_from_disk` reads a bill's candidate
`.txt` sidecar files back in record order to build the testimony text that
gets stored on the bill. This document explains why it is careful about how
much of each sidecar it reads, and the memory bug that carefulness fixes.

## Missing or unreadable sidecars are not bill failures

A record with no id has no path to build a sidecar path from. A sidecar
that was never written — because extraction has failed on every run so
far for that attachment — is simply treated as missing. Read errors become
"no sidecar" rather than failing the whole bill, the same
one-attachment-at-a-time isolation used everywhere else in this class.

## The per-bill cap, and why per-attachment caps do not add up to it

This composition step is the last size limit applied before the value is
written to a SQLite TEXT column. Per-attachment caps do not add up to a
safe per-bill cap on their own: 200 candidate attachments at
`MAX_ATTACHMENT_TEXT_CHARS` each comes to 100 million characters.

## The memory bug this fixed

The per-bill cap used to be applied AFTER `.filter_map.join` — that is, it
bounded only the final column, not the memory used to build it. Every
sidecar was read in full, collected into an `Array`, and joined into one
roughly 100-million-character `String` before the cap was even consulted.
That happens inside a Solid Queue worker on a Raspberry Pi with no spare
memory, so the actual failure mode was the worker process getting killed
mid-run, not the text getting trimmed as intended.

The fix builds the composed text up with an early exit instead: nothing
past the cap is opened at all.

## The same bug, one layer down: reading old sidecars

The READ from disk is now size-limited, not just the write to the column.
`cap_extracted_text` limits what the CURRENT version of the code writes,
but every sidecar left on the storage volume by an older version of the
code has no limit on it at all — and those older, larger sidecars are
exactly the files `#compose_testimony_from_disk` exists to re-read.
Reading an old 200 MB sidecar in full and only then trimming it would be
the same bug the composition loop had, just one layer further down the
call stack.

## Why `binread` with a byte limit, not `#read`

`binread` is used with an explicit byte limit rather than `#read`, because
the cap itself is counted in characters, and one character can take up to
4 bytes in UTF-8. Four times the character cap is therefore the smallest
byte limit that is guaranteed not to cut a valid sidecar short.

A multi-byte character that gets split at that byte boundary turns into
the replacement character U+FFFD once the scrub step runs — which is
exactly what the scrub step is for. `cap_extracted_text` then applies the
SAME character cap that the write path applies, so an old sidecar and a
freshly written one both contribute the same maximum amount of text — and
the cut stays visible in the text itself, because a cap nobody can see is
how lost evidence goes unnoticed.

## A sidecar's bytes are scrubbed on the way in

A sidecar written before the extractor started cleaning its own output can
still hold invalid UTF-8, and those bytes would otherwise go straight into
`extracted_testimony`. Any later regular-expression call on that text then
fails far away from here — `String#strip` in
`#compose_testimony_from_disk`, or `compact_blank` in the positions prompt
builder — inside rescue blocks that were written for entirely different
failures. The bytes are scrubbed on the way in specifically to prevent
that.

## Related parameters

- `max_bytes` — how much of the file to read. Callers that only INSPECT the
  text pass a smaller bound: stage 3 classification reads
  `CLASSIFICATION_READ_BYTES`, because the model is only ever shown up to
  `MAX_DOCUMENT_CHARS` of it. Composition itself keeps the
  default, larger bound.

## A second, higher cap for name-confirmed testimony

With the per-attachment cap lifted at runtime across a sample of Baltimore
bills, real testimony bundles were being clipped at the previous
500,000-character `MAX_ATTACHMENT_TEXT_CHARS`, the largest at nearly 3x
the cap. On one bill, the clipping took most of that
bill's testimony out of every downstream stage (letter splitting, reuse
grouping, campaign marking, the positions prompt), because those stages only
ever see what survived the attachment-level cut.

Raising `MAX_ATTACHMENT_TEXT_CHARS` itself was rejected: most attachments
that reach extraction are not testimony (bill text, procedural documents,
names the classifier still has to rule on), and a blanket increase would
have widened the sidecar-write and read-back cost for all of them for no
benefit. Instead, `MAX_TESTIMONY_ATTACHMENT_TEXT_CHARS` (2,000,000) applies
only to a record `FetchHearingsService#attachment_text_char_cap` classifies
as testimony, and every other record keeps `MAX_ATTACHMENT_TEXT_CHARS`
(500,000).

### Why the routing proxy is a name match, not the model verdict

`FetchHearingsService#call_discover` runs `#extract_attachments!` — which is
where `#cap_extracted_text` first applies a cap, at write time — before
`#classify_attachment_contents!`, the step that asks a language model whether
a still-undecided document is testimony. The model's verdict does not exist
yet when the write-time cap has to be chosen, so it cannot be the routing
signal.

`Testimony::NameRules.classify` IS available at that point — it runs
during discovery, earlier still — and its `:testimony` label is already the
proxy `Testimony::AttachmentClassifier::KEEP_LABELS` uses to skip the model
entirely for a name-confirmed match (see
`app/services/testimony/name_rules.rb` for what earns that label).
`#attachment_text_char_cap` reuses the same test:
`Testimony::NameRules.classify(record["name"]) == :testimony`. A record the
name rules leave `:ambiguous_bill_text`, `:procedural`, or `:undecided` —
still pending the model's read — keeps the base cap until a later run's
extraction sees it re-classified, if the classifier changes what a rename
resolves to.

`#read_attachment_txt`'s default `max_bytes` and its call into
`#cap_extracted_text` route through the same per-record cap. Without that,
raising only the write-time cap would let `extract_one_attachment` write a
larger sidecar, and then `#compose_testimony_from_disk`'s default read would
truncate it straight back down to the base cap on the very next read — the
fix would appear to work in the sidecar file and do nothing for the composed
column, which is the value every downstream stage actually consumes.

`Testimony::CoverageReport#attachment_cut_cap` needed no change: it already
reads the applied cap back out of the stored truncation notice
(`"extracted text truncated to <N> chars"`) rather than a constant, so it
reports 500,000 or 2,000,000 correctly depending on which cap actually fired
for that attachment.

### `NameRules` is global — this is not a Baltimore-only change

`Testimony::NameRules` classifies by pattern, with no locale gate, a fact
another feature relies on too. Raising the cap for
`:testimony`-classified attachments therefore applies identically to
Maryland and US Congress attachments once those locales fetch hearings
through this service, not only to Baltimore's. That is judged acceptable
here — a document a locale-neutral word list confirms as testimony is
exactly the kind of document this cap exists to stop clipping, regardless of
locale — but it is a real scope expansion, not an incidental one, and is
recorded here rather than left implicit.

### Why the composed cap had to move too

`MAX_COMPOSED_TESTIMONY_CHARS` bounds the composed value
`FetchHearingsService#compose_testimony_from_disk` builds across every
attachment on a bill, and raising the per-attachment cap without raising it
would only relocate the clipping: the same measurement run left
`MAX_COMPOSED_TESTIMONY_CHARS` at 2,000,000 on purpose, to see whether it
would bind once the per-attachment cap stopped. It never bound on any of the
ten bills — but bill 25-0064 composed to 1,995,251 characters, 0.24% under
the 2,000,000 cap, while carrying two large testimony bundles (712,371 and
1,245,541 characters, uncapped in that run). A bill with even one more
attachment of that size, or a slightly larger one, would have crossed the
old composed cap — and unlike the per-attachment cap, the composed cap cuts
wherever `MAX_COMPOSED_TESTIMONY_CHARS` falls inside the joined text, which
is generally mid-letter rather than at an attachment boundary.

`MAX_COMPOSED_TESTIMONY_CHARS` moved to 8,000,000: four times
`MAX_TESTIMONY_ATTACHMENT_TEXT_CHARS`, so a bill carrying up to four
testimony attachments each at the new per-attachment cap still composes
without hitting the composed cap, and the new composed cap sits well clear
of the 1,995,251 already measured on the phase's own headline bill — not at
the same near-miss distance the old pairing (500,000 / 2,000,000, also a 4x
ratio) left 25-0064 sitting at, this time measured against the raised
per-attachment cap rather than the old one.

Composition's memory bound (see "The memory bug this fixed" above) is
unaffected by either change: the early-exit loop still stops reading
sidecars the moment the running total crosses `MAX_COMPOSED_TESTIMONY_CHARS`,
so a larger composed cap means a larger maximum resident string (at most
8 MB of ASCII text) rather than a return to reading every candidate's
sidecar in full.

## Three size bounds, one per layer (as the service stands today)

Note: the constants named below (`MAX_ATTACHMENT_TEXT_CHARS = 500_000`,
`MAX_COMPOSED_TESTIMONY_CHARS = 2_000_000`) are the values actually in
`fetch_hearings_service.rb` today. They do not match the name-confirmed-cap section
above, which describes a later `MAX_TESTIMONY_ATTACHMENT_TEXT_CHARS` /
`attachment_text_char_cap` split and an 8,000,000 composed cap that are not
present in the current source. That drift is called out here rather than
silently resolved.

Three size bounds exist, one per layer, on top of the Faraday profile's 30s
TIME bound (before these, no SIZE bound existed at all):

1. **Downloaded bytes** — `Legistar::AttachmentFetch::MAX_ATTACHMENT_BYTES`.
   It lives there because there are two download sites
   (`FetchBillsService#download_pdf` and
   `FetchHearingsService#download_attachments!`) and it belongs wherever
   the download happens. Keeping it at the shared seam is what once let
   `FetchBillsService#download_pdf` write an unbounded body; see
   `docs/explanation/attachment-fetch-safety-checks.md`.
2. **A single attachment's extracted text** — `MAX_ATTACHMENT_TEXT_CHARS`
   (500,000). It sits well above
   `BillPositionsPromptBuilder.max_testimony_chars` (150k in production),
   so nothing that could ever have reached the prompt is lost — this bounds
   the sidecar write and the memory held while composing, not the
   evidence. "The memory held while composing" was not always true: the
   cap once applied to `#cap_extracted_text` (the write) only, while
   `#read_attachment_txt` read whole sidecars — including unbounded ones
   left by runs predating the cap — and `#compose_testimony_from_disk`
   materialized all of them before consulting
   `MAX_COMPOSED_TESTIMONY_CHARS`. Both now honor it: the read is
   byte-bounded at 4x this cap (one char is at most 4 UTF-8 bytes) and then
   capped to it, and composition stops at the composed cap.
3. **The composed value** written to
   `BillLlmProvisioning#extracted_testimony` — `MAX_COMPOSED_TESTIMONY_CHARS`
   (2,000,000). Also the point composition STOPS reading sidecars, not
   merely the point the composed value is clipped.

## `CLASSIFICATION_READ_BYTES`: reading whole sidecars for classification would OOM the Pi

How many bytes of a sidecar stage 3 reads to classify its document
(`CLASSIFICATION_READ_BYTES = Testimony::ClassificationPromptBuilder::MAX_DOCUMENT_CHARS * 4`).
The model is only ever shown `MAX_DOCUMENT_CHARS` (2,000) characters, so
reading whole sidecars bought nothing and cost everything:
`MAX_ATTACHMENT_CANDIDATES` (200) times `MAX_ATTACHMENT_TEXT_CHARS`
(500,000) is 100 million characters held at once across every model round
trip — an out-of-memory kill on the small production host, the same shape
`#compose_testimony_from_disk` was already rewritten to avoid.
Bounded, the same 200 candidates hold at most ~1.6 MB. 4 bytes per
character is the UTF-8 worst case, so the read can never come back shorter
than `MAX_DOCUMENT_CHARS` characters for a document that has them.

The trade, stated: the prompt builder collapses whitespace BEFORE cutting
to `MAX_DOCUMENT_CHARS`, so a document whose opening bytes are mostly
whitespace can now show the model a shorter opening than a full read would
have. This bound sits 4x above `MAX_DOCUMENT_CHARS`, so the collapse must
shrink the opening by more than 4x before the model sees less than the cut
would have shown it either way.

`MAX_ATTACHMENT_CANDIDATES` (200) is a separate bound on the candidate
array itself, guarding against a hostile or degenerate matter with an
endless attachment list making discovery iterate forever. Baltimore
matters observed in production (e.g. bill 25-0064) run ~30 attachments;
200 leaves generous headroom.
