---
lat:
  mode: explanation
---

# Why BillPositionsPromptBuilder's limits are set where they are

See also: `docs/reference/bill-positions-prompt-limits.md` for the exact values and what each one bounds, and [[distributed-testimony-pipeline]] for how chunked testimony processing works across stages.

## Why testimony gets its own, smaller budget

Testimony gets a limit of its own, separate from `BillSummaryPromptBuilder.max_source_chars`.

Testimony is backing evidence for a positions call, not the main document a summary is built from, so it gets a smaller budget: 150,000 characters in production and 45,000 in development, against 300,000/45,000 for `max_source_chars`.

## The budget that actually matters is measured in tokens

A character count bounds nothing the cap exists to protect — context window, price, how much evidence the model can hold — because all three are counted in tokens.

`max_testimony_chars` converts a token budget into a character ceiling so the rest of the class can keep comparing plain string lengths.

### Why the conversion floor is 1.7 characters per token

`TESTIMONY_CHARS_PER_TOKEN_FLOOR` is the FEWEST characters one token has been seen to carry in real testimony, so dividing by it can only over-count tokens and cut early, never late.

Measured with llama.cpp `/tokenize` over the first 150,000 characters of the three bills that exceed the cap: 3.21, 2.89 and 1.73 characters per token. Nothing approached `Llm::PromptCache::CHARS_PER_TOKEN` (3.5), which is why 150,000 characters was ever read as roughly 43,000 tokens when on one bill it is really 86,767.

This is deliberately NOT `PromptCache`'s constant. There, under-counting tokens only withholds a cache marker that would have paid off; here the same under-count would let a document through at twice the intended size.

### Why both a character bound and a token bound apply

BOTH bounds apply, and the tighter one wins.

On today's settings the character bound is tighter, so nothing that works now is cut any harder. The token bound is the ceiling that stops a badly-tokenizing document — dense tables, heavy OCR artifacts, both of which arrive in public PDFs — from spending 150,000 tokens out of a 150,000-character allowance.

Every comparison against the cap reads `self.max_testimony_chars`, so the truncation notice can never name a different set of sources than the cut really dropped.

`self.bounded_testimony_chars` is a method rather than an expression baked into a constant, so a test can drive it with a token budget that actually binds: on today's settings the two bounds land on the same number, and a check that compares them could otherwise pass whether or not the clamp is there at all.

### Why the settings are read per call, not frozen into constants

`self.max_testimony_tokens`.

`self.max_testimony_tokens`, `self.max_testimony_chars`, and `self.max_summary_context_chars` all read their setting on every call rather than freezing it into a constant, so a test can vary the setting (`with_app_config(:llm, llm_max_testimony_tokens: ...)`) for the length of one example — impossible with a constant.

Zero and negative still fall back to the declared default in each case: the strict integer caster on `Sway::Settings::Llm` stops only the OTHER failure, unreadable text becoming a silent zero. A real, readable zero or negative value still means "use the default". For `max_testimony_chars` specifically, a `LLM_MAX_TESTIMONY_CHARS` of `0` would otherwise quietly cut the testimony down to nothing.

`max_testimony_chars`'s clamp against `max_testimony_tokens` sits in the same method, in the same order it always ran in: read the raw override, fall back to the default on zero or negative, then clamp against the token bound — now a method call rather than a constant, so raising the character cap alone can never raise the amount of testimony that reaches the prompt past what the token bound allows.

## Why the bill-summary context is capped small

The whole design of using `llm_summary` as context (see `docs/explanation/bill-positions-prompt-architecture.md`) rests on the summary being SHORT.

The whole design of using `llm_summary` as context (see `docs/explanation/bill-positions-prompt-architecture.md`) rests on the summary being SHORT — short enough to orient the model without outweighing the testimony it is meant to orient. The output schema asks the summary generator for 2-4 sentences, but nothing makes the model obey, and it is free to return a page. `max_summary_context_chars` turns that assumption into a fact. It is small on purpose: this is context, and a summary long enough to be cut here has already stopped being context.

### Why the "honours a smaller llm_max_summary_context_chars" example fills with "Z"

Before `self.max_summary_context_chars` read its setting per call per call, a test could not vary this cap at all — it was resolved once, when the file was first autoloaded.

`with_app_config` sets it for the length of one example, and the builder honours the new, much smaller value. The fixture summary is filled with the letter "Z" because the enclosure's fixed identity lines (`"Bill number:"`, `"Title:"`) and the rest of the prompt (e.g. the word "context") contain no "Z", so a count of it is a count of exactly what the summary contributed.

## Why the identity label bounds live in this class

`MAX_BILL_NUMBER_CHARS` and `MAX_BILL_TITLE_CHARS` are restated here rather than borrowed from `BillSummaryPromptBuilder::MAX_METADATA_FIELD_CHARS`, for the reason `Llm::PromptLabel` gives.

`MAX_BILL_NUMBER_CHARS` and `MAX_BILL_TITLE_CHARS` are restated here rather than borrowed from `BillSummaryPromptBuilder::MAX_METADATA_FIELD_CHARS`, for the reason `Llm::PromptLabel` gives: one builder's limit must never become a side effect of another builder's measurements.

`bill.title` is the one that actually needs a bound. It arrives as Legistar's `MatterTitle` with no column validation and no length limit — real titles can run to thousands of characters. `bill.external_id` is already held to 64 path-safe characters by `Bill::EXTERNAL_ID_PATTERN` whenever it changes, so its bound here is a guard at the boundary rather than a live need.

## Why the draft-position bounds are read from the schema, not typed out again

`MAX_DRAFT_POSITIONS`, `MAX_ORG_NAME_CHARS`, and `MAX_POSITION_SUMMARY_CHARS` are the bounds the model's answer is CHECKED against, read from the schema file rather than typed out again here.

`MAX_DRAFT_POSITIONS`, `MAX_ORG_NAME_CHARS`, and `MAX_POSITION_SUMMARY_CHARS` are the bounds the model's answer is CHECKED against, read from the schema file rather than typed out again here — the same arrangement `BillLlmProvisioning::DRAFT_POSITIONS` uses, with `fetch` all the way down so a restructured schema raises at boot instead of quietly telling the model a limit that is not the one actually enforced.

They are stated in the prompt because a payload past a bound is discarded WHOLE, after the call has already been paid for. A model that is not told the limit cannot keep to it.

## Scrub, neutralize, then measure — in that order, for testimony

`#testimony_sources` and `#truncate_testimony` scrub for invalid bytes, then neutralize, then measure — in that order, for three separate reasons.

The scrub has to come first because the neutralize step runs regular expressions, which raise on invalid bytes.

Scrubbing happens BEFORE the blank check, not after: `String#blank?` runs a regular expression too, so it raises on invalid UTF-8 the same way the defusing inside `Llm::UntrustedTextBlock#wrap` does. `TestimonyTextExtractor` scrubs at the source now, but that does not clean rows earlier builds already saved, and `supplemental_testimony` comes in through a different channel entirely — this is the last check before the prompt.

The neutralize step has to come before the length is measured, or the cap is measured on text the enclosure has not finished rewriting. `Llm::UntrustedTextBlock#wrap` rewrites each registered prefix as a longer replacement, so a cap applied to the raw text is not a cap on what is actually sent — 150,000 characters of nothing but boundary markers left this builder as 216,658. Neutralizing at the source puts `#combined_testimony`, `#truncate_testimony`, and `#cut_source_names` all in the units the model will actually receive, and the second pass inside `#wrap` is then a no-op, because the substitution is idempotent. Neutralizing happens per source, rather than after the join, so the offsets `#cut_source_names` walks stay the offsets of the text it is naming; a prefix cannot straddle `SOURCE_SEPARATOR`, so either order gives the same string.

NO COLLAPSE happens here, deliberately — unlike the bill-summary label (see `docs/explanation/bill-positions-prompt-security.md`). A witness statement's paragraphing is evidence the positions call is grounded on, and `#testimony_section` gives it its own enclosure with no labels inside for it to forge.

## Why the join order is a bug fix, not a stylistic choice

`#testimony_sources` returns the ONLY two inputs to this builder, in the order they are joined, each paired with the name the truncation notice uses for it.

THE ORDER IS THE FIX. The sources are joined FIRST and cut ONCE from the end — never cut each source on its own first, or a bill with many short attachments would get every one near the cap clipped, while a bill with one huge attachment gets the same total budget. But a cut that takes the tail throws away whichever source is joined LAST, and that source used to be `supplemental_testimony`: the column an operator fills in by hand when the Bill Creator tells them an attachment failed extraction (`FetchHearingsService` says "paste the testimony text into Supplemental testimony below").

The two budgets do not agree — `FetchHearingsService` lets `extracted_testimony` reach 2,000,000 characters, and a single attachment 500,000, against `max_testimony_chars`' default of 150,000 — so one large attachment used to spend the whole budget before the paste was reached, and the remedy the admin screen offers never got to the model. The paste goes FIRST because it is hand-curated and small; the machine-composed bundle absorbs the cut instead.

## Why TRUNCATION_NOTICE is a format template, not a fixed string

`TRUNCATION_NOTICE` used to say only that testimony had been truncated, which cannot tell an operator that the paste they added to work around a failed extraction is the part that never reached the model.

`%{cut}` names the source, or sources, that did not arrive whole.

## cut_source_names: naming a source that was cut partway through, or displaced entirely

`#cut_source_names` walks `#testimony_sources` in join order and names a source when its OWN END lands past the cap.

`#cut_source_names` walks `#testimony_sources` in join order and names a source when its OWN END lands past the cap — which covers both "cut partway through" and "displaced entirely", the two ways a source can fail to reach the model whole.

## Why oversized organization letters are windowed

Individual organization letters exceeding `MAX_SINGLE_LETTER_CHARS` (12,000 characters) are bounded to 9,000 head characters and 3,000 tail characters to prevent a single lengthy study from exhausting prompt budgets.

A window notice marks the omitted middle. Preserving the first 9,000 characters retains letterheads, executive summaries, and formal stance declarations, while the final 3,000 characters retain concluding remarks and organizational signature blocks.

## Why testimony is partitioned across chunked payloads

Nameable testimony letters that exceed a single prompt budget are partitioned across up to `max_positions_chunks` payloads.

A single positions prompt budget (150,000 characters in production, 45,000 in development) cannot accommodate hearing bundles with dozens of distinct organizational submissions. Rather than truncating testimony and dropping letters at the tail of the bundle, `BillPositionsPromptBuilder` partitions nameable letters across chunked payloads.

Partitioning operates strictly on whole-letter boundaries. Slicing an individual letter across chunks would fragment organizational arguments across separate model calls, producing incomplete or hallucinated positions. Closing each chunk cleanly on letter boundaries preserves complete witness context.

Chunk 0 carries `supplemental_testimony`, published opinion commentary, and news reporting alongside initial testimony letters, because operator-curated testimony and news articles only need evaluation once. Subsequent chunks carry only the bill context and their respective partition of testimony letters. If testimony exceeds all allowed chunks, the final chunk truncates with `TRUNCATION_NOTICE`.
