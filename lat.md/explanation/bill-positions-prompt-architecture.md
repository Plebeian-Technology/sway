---
lat:
  mode: explanation
---

# How BillPositionsPromptBuilder assembles the bill-positions prompt

`BillPositionsPromptBuilder` builds the prompt for the LLM call that works out which organizations, or individuals, back or oppose a bill.

Sibling prompt builders handle summary generation and testimony classification. Additional explanation files describe outside text defenses, prompt size limits, and [[distributed-testimony-pipeline|distributed bill testimony processing]].

## Evidence sources: hearing testimony, published opinion, and news reporting

The evidence consists of legislative hearing testimony, administrator-approved published opinion commentary, and administrator-approved news reporting.

Neither the bill diff nor the extracted statutory bill text serves as evidence for organization positions. The model reasons strictly from public hearing letters, published opinion pieces with established stances, and factual reporting articles where authorized institutional representatives are directly quoted.

Context is provided by the generated `llm_summary`, added as clearly labeled context rather than evidence. The model is instructed to treat the summary solely as reference context for resolving legislative bill references in the testimony or articles, never as evidence of an organization's stance.

The output matches `config/schemas/bill_positions.json` (`BILL_POSITIONS_SCHEMA`). The schema defines `draft_org_positions` for committee and news-sourced positions, and optional `draft_news_testimonies` for published opinion commentary, with `additionalProperties: false`.

## News reporting and spokesperson direct-quote extraction

Approved news reporting articles appear under `## News reporting` inside a dedicated untrusted enclosure.

Organization positions extracted from news reporting require direct quotations from authorized institutional spokespersons or officers speaking on behalf of the organization. Factual reporting articles differ from opinion commentary because reporting articles lack an administrator-assigned stance and document multiple perspectives within journalistic coverage.

Positions extracted from news reporting cite the backing article and text version identifier, the speaker name, the speaker role, and a verbatim excerpt containing the quotation in quotation marks. Journalist paraphrases, rank-and-file members, private individuals, public bodies, and news outlet attributions are excluded from organization positions. Summaries are formatted directly from the direct quotation and speaker attribution rather than a freeform paraphrase.

## Two pieces, split the same way as the sibling builder

`#system_prompt` (`header` + `output_contract`) and `#user_message` (`bill_context_section` + `testimony_section` + `published_opinion_section` + `news_reporting_section`) split the same way `BillSummaryPromptBuilder` does.

The split allows `GenerateBillSummaryJob` to build an `Llm::PromptPayload` from either builder in exactly the same way. The system part fills in nothing that changes from bill to bill, which allows caching; the user part changes per bill, which is why caching does not apply to it.

## Why sections are named, not positioned

Where the prompt text refers to another part of itself, it names the section — `## Required output`, `## Testimony` — instead of saying "above" or "below".

`#header` and `#output_contract` both follow this pattern because the same text is read under multiple orderings, making directional words unreliable.

`#output_contract` sits inside `#system_prompt`, which places it in the middle of the assembled prompt — between the header and the evidence sections — both under `#call` and under the API split (`[system_prompt, user_message].join`). Directional words such as "above" or "below" contradict the physical ordering across different consumers.

`#header` references to sections follow the same rule, avoiding relative placement descriptions such as "at the end".

A heading name remains accurate under every ordering and maintains byte-for-byte stability for prompt caching.

## Why call is kept, even though nothing in production calls it

Both LLM adapters take an `Llm::PromptPayload` that `GenerateBillSummaryJob` builds from `#system_prompt` and `#user_message` directly, so nothing in `app/` or `lib/` joins the two.

`#call` remains available as the whole-prompt inspection view for operators or console sessions, mirroring the sibling builder's `#call`.

It also provides end-to-end visibility into the testimony join order and supports test assertions against complete assembled prompts.

## system_prompt and user_message: which half is cacheable

`#system_prompt` is `[header, output_contract]` — the cacheable part of the prompt, since header and output_contract fill in nothing that changes from bill to bill.

`#user_message` is the per-bill part: the bill-context section, followed by joined hearing testimony, published opinion commentary, and news reporting. None of these components can be cached, since each varies per bill.

## Rebuilding cleaned testimony with per-letter headings and measuring reach

[[app/services/bill_positions_prompt_builder.rb#BillPositionsPromptBuilder]] rebuilds cleaned testimony with organization hints, excludes constituent self-letters, and measures reach across the full bundle.

`#cleaned_testimony_artifact` trusts `provisioning.cleaned_testimony` only when its text is present and `cleaned_testimony_at` is at least as recent as `testimony_fetched_at`. When the cleaning stage has not run or a later hearing fetch replaced `extracted_testimony`, `#testimony_sources` falls back to the raw column under `EXTRACTED_SOURCE_NAME` instead of `CLEANED_SOURCE_NAME` so any truncation notice names the source that actually reached the model.

When the artifact carries per-letter `source_kind` classifications and byte offsets, `#labeled_letters` validates each letter entry and filters out repeats, manually removed letters (`excluded: true`), and `person_speaking_for_self` constituent letters. Constituent self-letters and manually excluded letters are omitted because constituent letters are processed during `clean-testimony` (via campaign grouping, stance classification, and browsable testimony) and excluded letters were removed by an operator; keeping both out of the organization positions prompt prevents non-organizational mail from consuming character budget before organization letters are reached. When all letters in a bundle are repeats, excluded letters, or constituent letters, `#labeled_cleaned_text` returns an empty string rather than reverting to raw unlabelled text.

For nameable organization letters, `#letter_heading` formats `NAMEABLE_LETTER_HEADING` and appends structured organization hints when `extracted_org` is present with a non-blank `org_name`: `[extracted_org: Name | extracted_summary: Summary]`. Extracted attributes are scrubbed, collapsed, neutralized via `Llm::UntrustedTextBlock`, and stripped of pipe and bracket characters so untrusted text cannot forge attributes or break enclosure boundaries.

Because per-letter headings and separators spend part of the character allowance after `supplemental_testimony` is joined first, `#testimony_reach` is the single place that calculates how many stored characters and letters reach the model (`#labeled_reach`, `#unlabeled_cleaned_reach`, and `#extracted_reach`). `#labeled_reach` credits excluded constituent self-letters, manually removed letters (`excluded: true`), and repeats in full toward `reached_letters` and `reached_chars` without consuming the prompt budget allocated for nameable organization letters. [[app/services/testimony/coverage_report.rb#CoverageReport]] reads `#testimony_reach` directly and passes its locked `provisioning:` row into `.new(bill, provisioning:)` so in-transaction coverage checks never report false coverage gaps for intentionally excluded letters.

## Head+tail windowing for oversized organization letters

`#window_letter_body` bounds oversized organization letters exceeding `MAX_SINGLE_LETTER_CHARS` to preserve introductory stance context and signatory conclusions.

Letters within the 12,000-character threshold are returned unmodified. When an organization letter exceeds the limit, 9,000 characters from the head and 3,000 characters from the tail are joined with `LETTER_WINDOW_NOTICE`.

## Multi-chunk testimony partitioning and payload generation

`BillPositionsPromptBuilder` partitions nameable testimony letters across up to `max_positions_chunks` whole-letter chunked payloads.

`#prompt_payloads` pairs `#system_prompt` with each message in `#user_message_chunks`, generating an `Llm::PromptPayload` per chunk. For backward compatibility with single-prompt callers, `#user_message` returns the first chunk message, and `#call` returns the joined first chunk prompt.

Chunk 0 incorporates `bill_context_section`, `supplemental_testimony`, `published_opinion_section`, and `news_reporting_section`. Subsequent chunks (1 through `max_positions_chunks - 1`) include only `bill_context_section` and their allocated nameable letters, avoiding redundant token overhead for opinion and news context. When letters fit in chunk 0, `#user_message_chunks` returns a single-element array.

`#labeled_reach` evaluates reach across all generated chunks up to `max_positions_chunks`, allowing `TestimonyReach` to report complete coverage across multi-chunk bundles.

