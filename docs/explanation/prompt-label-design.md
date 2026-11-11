---
mode: explanation
summary: "Explains why Llm::PromptLabel collapses whitespace before enclosure, why it is the wrong tool for source text, and why the length limit deliberately lives with each caller instead of here."
status: agent-extracted
related: [untrusted-text-block-mechanics, bill-summary-prompt-security, bill-category-prompt-security]
---

# Why `Llm::PromptLabel` collapses whitespace, and where it stops

`Llm::PromptLabel` is one safe way to render every outside value a prompt
builder drops in as a LABEL — a bullet value, a numbered list item, a
`Bill:` line.

Squashing whitespace runs down to one space keeps such a value on its own
line: it can't fake a heading, a bullet, a code fence, or an extra list
entry. This protects the prompt's STRUCTURE.

## Why it is the wrong tool for source text

It is only right where the value has no structure of its own to lose — a
title, an external id, an attachment name. It is the WRONG tool for source
text or testimony, where the document IS structure.

## Why scrubbing has to run first

SCRUB FIRST, and that ordering is the whole reason this is a shared module
rather than three private methods. Both `gsub` and
`UntrustedTextBlock#wrap` raise `ArgumentError` on invalid UTF-8.

Every caller can hit that, since some columns were written before
`MupdfExtractor` started scrubbing at its own subprocess boundary. Those
raises land inside rescues written for other failures.

`BillsController#summary_prompt_prop` has no rescue at all (an unhandled
500), `GenerateBillSummaryJob` swallows it and fails the summary, and
`AttachmentClassifier#llm_verdicts` drops the whole batch.

This shipped as three copies of the same expression, each with its own
paragraph insisting on the ordering, two pointing at a sibling to say so.
`Llm::UntrustedTextBlock` was pulled from the same pair of files for the
same reason: one implementation to harden, not three to keep in sync.

## Why the length limit does not live here

The length LIMIT deliberately does not live here. Each caller sets its
own — 1,000 for a Baltimore title, 300 for an attachment name, 4,000 for a
summary.

`BillCategoryPromptBuilder`'s `MAX_TITLE_CHARS` comment records why those
numbers are restated rather than shared: one builder's limit should never
depend on another's unrelated measurements.
