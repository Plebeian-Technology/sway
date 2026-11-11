---
mode: reference
summary: "Lists each size and count limit BillSummaryPromptBuilder applies before assembling the bill-summary prompt, and what happens when a value exceeds it."
status: agent-extracted
related: []
---
# BillSummaryPromptBuilder size and count limits

<!-- vale Vale.Spelling = NO -->

`BillSummaryPromptBuilder` bounds several values before they go into the
bill-summary prompt. This page lists each limit, what it bounds, and what
happens when a value goes over it. For the measurements and history behind
each number, see `docs/explanation/bill-summary-prompt-limits.md`.

## The limits

| Constant / method | Value | What it bounds | What happens on overflow | Override |
| --- | --- | --- | --- | --- |
| `self.max_source_chars` (reads `Sway::Settings.llm.llm_max_source_chars`) | Production: 300,000 characters. Local dev: 45,000 characters. Test: uses the production value. | The bill source text embedded in `#source_text_section` (diff markdown or extracted text). | The text is cut to the limit and `TRUNCATION_NOTICE` is appended, telling the model and any reading operator that the summary is based on a partial source. The start of the document is kept; the end is cut. | `LLM_MAX_SOURCE_CHARS` environment setting overrides the cap in any environment. A value of zero or negative falls back to the default. |
| `MAX_METADATA_FIELD_CHARS` | 1,000 characters | Single outside-sourced LABEL values rendered by `#sanitize`: `bill.title`, `bill.external_id`, and a parsed section's `title`. Not the bill's source text. | The value is truncated to 1,000 characters. | None. |
| `MAX_CITATION_KEYS` | 250 rows | How many rows `#citation_allow_list_section` renders from `bill.bill_section_references`. | Rows past the 250th are dropped and counted in the overflow note appended to the section. | None. |
| `MAX_CITATION_SECTION_CHARS` | 50,000 characters | The total assembled size, in characters, of the citation allow-list section once `MAX_CITATION_KEYS` rows are joined (the product of row count and row size). | Rows past the budget are dropped whole (never truncated mid-row) and counted in the same overflow note as rows past `MAX_CITATION_KEYS`. | None. |
| `MAX_CATEGORIES` | Reads `maxItems` from `config/schemas/bill_summary.json` (`BILL_SUMMARY_SCHEMA_HASH`) | The upper bound on how many categories the prompt asks the model to choose. | A reply with more categories than this is rejected WHOLE by schema validation before anything else looks at it — the whole summary is lost, not just the extra categories. On the paste path (an operator pasting a response by hand) it is the operator's entire pasted body that is refused. | None; this is not independently configurable, it always tracks the schema. |

## Related pointers

- `TRUNCATION_NOTICE` — the fixed string appended when `#truncate_source`
  cuts the source text.
- `SOURCE_DELIMITER_PREFIX`, `METADATA_DELIMITER_PREFIX`,
  `CITATION_DELIMITER_PREFIX` — the `Llm::UntrustedTextBlock` enclosure
  prefixes that wrap the content these limits bound. See
  `docs/explanation/bill-summary-prompt-security.md`.
