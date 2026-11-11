---
lat:
  mode: explanation
---

# How BillCategoryPromptBuilder defends the categorize prompt against outside text

`BillCategoryPromptBuilder` builds a categorize-only prompt for assigning categories to a bill that has already been summarized.

It tells the LLM to pick up to `MAX_CATEGORIES` categories from the provided list of active categories and reply with a JSON object `{"categories": [...]}`. Called by the backfill path, which loads active categories once and passes them in — avoiding one query per bill on bulk categorization runs.

## Why the bill's summary cannot be trusted

The bill's stored `llm_summary` cannot be trusted.

An LLM wrote it from bill text that came from outside, so someone may have planted instructions in it aimed at whichever model reads it next. `#system_prompt` therefore carries a paragraph telling the categorizing model to treat the summary as material to read, not as orders to follow — the same paragraph `BillSummaryPromptBuilder#header` carries.

## The gap this closed

That warning has something to point at now.

`#user_message` once interpolated the summary — and the Legistar-sourced `bill.title` — bare, with no fence and no delimiter, making this the one prompt builder in the app that embedded untrusted text unenclosed. Worse, the same `llm_summary` IS enclosed when `BillPositionsPromptBuilder` embeds it, so the identical class of content was protected at only one of its two sites.

Both values now go inside a single `Llm::UntrustedTextBlock.for(:bill_context)` enclosure: the SAME registered content class, because it is literally the same material, and this prompt renders one block so there is no sibling block to tell it apart from.

## Why MAX_TITLE_CHARS restates the same number rather than referencing it

`MAX_TITLE_CHARS` (1,000) is the length cap on the title, which comes from outside this system.

It equals `BillSummaryPromptBuilder::MAX_METADATA_FIELD_CHARS`, deliberately the same number for the same value: this is the same `bill.title`, from the same Legistar feed, and the measurement behind that figure applies unchanged. It is restated rather than referenced because the two builders are otherwise independent, and a cross-class constant reference would make this one's cap a function of the other one's unrelated decisions.

## Why MAX_SUMMARY_CHARS mirrors BillPositionsPromptBuilder's cap

`MAX_SUMMARY_CHARS` (4,000) mirrors `BillPositionsPromptBuilder.max_summary_context_chars`, which caps the SAME `llm_summary` for the same reason.

`MAX_SUMMARY_CHARS` (4,000) mirrors `BillPositionsPromptBuilder.max_summary_context_chars`, which caps the SAME `llm_summary` for the same reason: `#system_prompt` asks for a short summary and nothing enforces that, so a model is free to return a page. Here the cost of a runaway value is a paid categorize call whose prompt is mostly one field.

`SUMMARY_TRUNCATION_NOTICE` is said out loud rather than silently clipped, because the summary is the material the categories are chosen FROM — an operator reading this prompt should be able to tell that the choice was made on a partial value. The title gets no equivalent notice: a truncated title is still a title, and `BillSummaryPromptBuilder#sanitize` clips the same value silently.

## Why MAX_CATEGORIES is read from the schema, not typed out again

`MAX_CATEGORIES` is read from the schema the answer is CHECKED against rather than typed out again in the prompt — three times, as it was.

The schema is the authority and the prompt follows it: a reply past `maxItems` is rejected whole by the adapter, after the call has been paid for, so asking for more than the schema takes discards paid work (the sibling site of `BillSummaryPromptBuilder::MAX_CATEGORIES`). `fetch` runs all the way down, so a restructured schema raises at boot instead of quietly telling the model a limit that is not the one enforced.

## boundary_instruction: fixed prefix only, for the same caching reason

`#boundary_instruction` names only the FIXED prefix of the boundary marker.

Adding the random per-instance suffix would make this system block different on every call. Anthropic's cache only matches an exact prefix, so nothing would ever be read back from the cache while every call still paid the surcharge for writing to it.

## user_message: why collapsing to one line is the right control here

The title and summary are scrubbed before the enclosure, like every other externally-derived read: `Llm::UntrustedTextBlock#wrap` runs regexps, which raise `ArgumentError` on invalid bytes.

Rows written before `MupdfExtractor` scrubbed at its own subprocess boundary can still carry such bytes, and this runs inside `BackfillBillCategoriesJob`'s `find_each`, where one bad row would kill the whole job.

They are also collapsed to one line, and length-capped. The scrub and the enclosure were two of the four parts of the treatment every sibling builder applies; this site shipped with the other two missing, which left the body's only structural marker — the `Summary:` label — forgeable by the title above it. Real titles already carry embedded newlines, so a title reaching this method with `\n\nSummary:\n...` inside it is one Legistar copy-paste away, not an exploit.

Neither value's meaning depends on its line structure here: the model is picking a few names from a fixed list, and the paragraphing of a summary carries nothing that decides which. That is what makes collapsing the right control at THIS site and the wrong one at `BillSummaryPromptBuilder`'s source-text enclosure, where the document IS the structure.

## bounded_title/bounded_summary: bounds are measured after neutralize, not before

Both bounds are measured AFTER `Llm::UntrustedTextBlock.neutralize`, because `#wrap` rewrites each registered prefix as a longer replacement — so a bound taken before it is not a bound on what gets sent.

This is the same shape and the same fix as the two summary prompt builders; found by grepping every `#wrap` call site for a cap applied to the raw text. The replacement carries no whitespace, so it cannot undo `Llm::PromptLabel.collapse`'s one-line guarantee.
