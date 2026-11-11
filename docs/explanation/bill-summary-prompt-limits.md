---
mode: explanation
summary: "Explains why each size and count cap in the bill-summary prompt builder is set to its specific value."
status: agent-extracted
related: []
---

# Why BillSummaryPromptBuilder's limits are set where they are

<!-- vale Vale.Spelling = NO -->

See also: `docs/reference/bill-summary-prompt-limits.md` for the exact
values and what each one bounds.

## Why the source-text cap differs by environment

`self.max_source_chars` caps how much source text goes into the prompt, so
the whole prompt fits in the model's context window (how much text a model
can read at once). The largest Baltimore bills carry 1.2-1.4 MB of
extracted text, roughly 350-400k tokens. That is far past what either model
will accept: the local llama.cpp model stops at a 128k-token window and
rejects the request outright (HTTP 400 `exceed_context_size_error`) before
doing any work. The right cap depends on which model sits behind the
adapter, so it differs by environment:

* **Production** — the Claude API. 300,000 characters, about 90-100k
  tokens of dense legislative text, fits with room left over for the
  response and the surrounding instructions.
* **Local dev** — a small llama.cpp server that hit `Net::ReadTimeout` on
  300,000-character prompts, so the cap is 45,000: the size that finishes
  inside the request timeout (a 45k-character bill took about 38 seconds).

Test keeps the production cap. LLM calls are stubbed there, so nothing can
time out and the truncation spec stays stable. `LLM_MAX_SOURCE_CHARS`
overrides the cap anywhere.

## Why the cap is read per call, not frozen into a constant

`self.max_source_chars` reads the cap on every call rather than freezing it
into a constant, so a test can vary the setting
(`with_app_config(:llm, llm_max_source_chars: ...)`) for the length of one
example — impossible before this method existed, since the old
`MAX_SOURCE_CHARS` constant was resolved once, when this file was first
autoloaded. Zero and negative still fall back to the
default: `Sway::Settings::Llm`'s strict integer caster stops only the OTHER
failure, unreadable text becoming a silent zero — a real, readable
zero or negative value still means "use the default" here, unchanged from
before this migration. A `LLM_MAX_SOURCE_CHARS` of `0` would otherwise
quietly cut the source down to nothing and ship a prompt with no bill in it.

The fallback reads `Sway::Settings::Llm`'s own declared default rather than
restating the `Rails.env.development?` conditional here as a second
literal — two independent copies of the same number is what let them drift
with nothing to notice.

The "honours the smaller cap" example (`when llm_max_source_chars is set
smaller for one example`) fills the fixture source with the letter "Z"
because no fixed word in this class's prompt templates contains it, so a
count of "Z" in the rendered prompt is a count of exactly what the source
contributed.

## Why `MAX_METADATA_FIELD_CHARS` is 1,000

`MAX_METADATA_FIELD_CHARS` limits single outside-sourced values rendered as
short LABELS — `bill.title`, `bill.external_id`, and a parsed section's
title. None of these is the bill's text; that goes through
`#source_text_section`, which has its own, far larger limit
(`self.max_source_chars`).

It is 1,000 characters rather than the 300 that
`Testimony::ClassificationPromptBuilder` uses for attachment names, because
a Baltimore `MatterTitle` is a full ordinance preamble, not a label. Real titles are often longer than 300 characters, so a 300-character limit would cut most of them off mid-sentence. At 1,000 characters it cuts only the multi-thousand-character bond-issue preambles, whose endings are boilerplate, while still stopping a
hostile or broken value from swamping the prompt.

## Why `MAX_CITATION_KEYS` is 250

`MAX_CITATION_KEYS` limits HOW MANY allow-list rows are rendered, as
opposed to `MAX_METADATA_FIELD_CHARS`, which limits the size of each one.

`#citation_allow_list_section` was the only list in this prompt with no
limit on its length, and its rows are not the application's own data:
`ParseSectionsService` writes one `BillSectionReference` for every section
citation its pattern finds in `bill.extracted_text`, and `extracted_text`
still carries the whole public hearing testimony bundle (see
`#truncate_source`). Anyone may submit a PDF to a Baltimore City Council
hearing, so the number of rows is something outsiders influence, not a
fact about the legislation.

250 was chosen to sit above the row count of every real bill. It is the same shape as the
cap this constant used to name,
`Testimony::AttachmentClassifier::MAX_ATTACHMENTS_PER_BATCH` — cap the list,
then say what was left over rather than pretending it was not there. That
other number later became a slice size rather than a cap,
because its leftovers were being let through unclassified. This
one still caps, and still says what it dropped.

A row count alone does not bound the assembled SECTION — see the next
section for the product bound.

## Why `MAX_CITATION_SECTION_CHARS` is 50,000

`MAX_CITATION_SECTION_CHARS` bounds the assembled allow-list section, in
characters — the bound on the PRODUCT that the two limits above leave open. `MAX_CITATION_KEYS` bounds the rows and
`MAX_METADATA_FIELD_CHARS` bounds each key and each title, but nothing
bounded rows times row size: 250 rows of a maximal key and title run to
about 500,000 characters, 1.67x what `self.max_source_chars` returns — in
the one section whose rows outsiders can mint (see the `MAX_CITATION_KEYS`
section above). An earlier comment here claimed 250 rows were "far below
anything that could swamp the prompt", which is false in exactly the
hostile case the cap was added for.

Against real data, 50,000 is several times the worst bill's assembled rows, so no real data is ever cut, while holding the section to a sixth of
what `self.max_source_chars` returns in the hostile case. Rows past this
budget are dropped whole and counted in the same overflow note as rows past
`MAX_CITATION_KEYS`.
