---
mode: reference
summary: "Lists each size and count limit BillPositionsPromptBuilder applies before assembling the bill-positions prompt, and what happens when a value exceeds it."
status: agent-extracted
related: []
---

# BillPositionsPromptBuilder size and count limits

<!-- vale Vale.Spelling = NO -->

`BillPositionsPromptBuilder` bounds several values before they go into the
bill-positions prompt. This page lists each limit, what it bounds, and what
happens when a value goes over it. For the measurements and history behind
each number, see `docs/explanation/bill-positions-prompt-limits.md`.

## The limits

| Constant / method | Value | What it bounds | What happens on overflow | Override |
| --- | --- | --- | --- | --- |
| `self.max_testimony_chars` (reads `Sway::Settings.llm.llm_max_testimony_chars`, clamped by `self.max_testimony_tokens`) | Production: 150,000 characters. Local dev: 45,000 characters. Whichever of the character bound or the token bound (see below) is tighter. | The joined testimony text embedded in `#testimony_section`. | The joined text is cut to the limit and `TRUNCATION_NOTICE` is appended, naming which source(s) the cut fell in. The start is kept; the end is cut. | `LLM_MAX_TESTIMONY_CHARS` overrides the character half. A value of zero or negative falls back to the default. |
| `self.max_testimony_tokens` (reads `Sway::Settings.llm.llm_max_testimony_tokens`) | Token budget the model's context window must hold. | Used only as an input to `self.bounded_testimony_chars`, converting a token budget into a character ceiling. | N/A — see `max_testimony_chars`. | `LLM_MAX_TESTIMONY_TOKENS` overrides it. A value of zero or negative falls back to the default. |
| `TESTIMONY_CHARS_PER_TOKEN_FLOOR` | `1.7` | Fewest characters one token has been observed to carry in real testimony. Used to convert `max_testimony_tokens` into a character ceiling. | N/A — a fixed constant, not a runtime cap. | None. |
| `self.bounded_testimony_chars(chars, tokens, chars_per_token_floor)` | `[chars, (tokens * chars_per_token_floor).floor].min` | Whichever of the character allowance or the token-derived allowance is tighter. | N/A — a pure function used by `max_testimony_chars`. | None. |
| `self.max_summary_context_chars` (reads `Sway::Settings.llm.llm_max_summary_context_chars`) | Configured value, or the declared default on zero/negative. | The bill-summary text embedded in `#bill_context_body`. | The summary is cut to the limit and `SUMMARY_TRUNCATION_NOTICE` is appended. | `LLM_MAX_SUMMARY_CONTEXT_CHARS` overrides the cap. A value of zero or negative falls back to the default. |
| `MAX_BILL_NUMBER_CHARS` | 200 characters | `bill.external_id`, rendered as `#bill_number_label`. | The label is truncated to 200 characters. | None. |
| `MAX_BILL_TITLE_CHARS` | 1,000 characters | `bill.title`, rendered as `#bill_title_label`. | The label is truncated to 1,000 characters. | None. |
| `MAX_DRAFT_POSITIONS` | Reads `maxItems` from `config/schemas/bill_positions.json` (`BILL_POSITIONS_SCHEMA_HASH`) | How many `draft_org_positions` entries the prompt asks the model to return. | A reply with more entries than this is rejected WHOLE by schema validation (`additionalProperties: false`), losing every position in it, not just the extras. | None; always tracks the schema. |
| `MAX_ORG_NAME_CHARS` | Reads `properties.draft_org_positions.items.properties.org_name.maxLength` from the same schema | The `org_name` field length the prompt asks the model to keep to. | Same as above — an over-length reply is rejected whole by schema validation. | None; always tracks the schema. |
| `MAX_POSITION_SUMMARY_CHARS` | Reads `properties.draft_org_positions.items.properties.summary.maxLength` from the same schema | The `summary` field length the prompt asks the model to keep to. | Same as above — an over-length reply is rejected whole by schema validation. | None; always tracks the schema. |

## Testimony source names and join order

`#testimony_sources` returns, in this fixed order:

1. `SUPPLEMENTAL_SOURCE_NAME` ("the testimony an operator pasted in") —
   `BillLlmProvisioning#supplemental_testimony`.
2. `EXTRACTED_SOURCE_NAME` ("the testimony extracted from the hearing
   attachments") — `BillLlmProvisioning#extracted_testimony`.

The two sources are joined with `SOURCE_SEPARATOR` (`"\n\n"`) FIRST, and the
combined text is cut ONCE from the end against `self.max_testimony_chars` —
never cut per source before joining. The names exist so
`TRUNCATION_NOTICE` can state which source(s) the cut fell in. See
`docs/explanation/bill-positions-prompt-limits.md` for why the order and
the join-then-cut sequence are load-bearing.

## Related pointers

- `TRUNCATION_NOTICE`, `SUMMARY_TRUNCATION_NOTICE` — the format strings
  appended when `#truncate_testimony` / `#truncate_summary_context` cut
  their input.
- `TESTIMONY_DELIMITER_PREFIX`, `CONTEXT_DELIMITER_PREFIX` — the
  `Llm::UntrustedTextBlock` enclosure prefixes that wrap the content these
  limits bound. See `docs/explanation/bill-positions-prompt-security.md`.
