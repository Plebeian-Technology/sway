---
mode: explanation
summary: "Why Testimony::ClassificationPromptBuilder judges attachments on their extracted text rather than their file name, and why its prompt is split into system_prompt and user_message."
status: agent-extracted
related: []
---

# Testimony classification prompt design

`Testimony::ClassificationPromptBuilder` builds the prompt for the last step
of `Testimony::AttachmentClassifier`: the language-model pass over
attachments `Testimony::NameRules` could not decide from the file name
alone. That classifier runs in three steps.

## Text is the evidence, not the name

The model is asked about the document's extracted text, not just its file
name. A document only reaches this step because its name was
already inconclusive, so judging it on that same name again would not work.

The name is still sent along, as supporting evidence rather than the only
evidence: an operator typed it, and a name like `"DOF 25-0064"` names the
agency that wrote the letter even when the letter's text does not. See
`ClassificationPromptBuilder::MAX_DOCUMENT_CHARS` for how much of each
document's text the model actually sees, and how that figure was measured
(an earlier, unsupported citation for it was corrected).

## Why the prompt is split into two methods

`#system_prompt` and `#user_message` mirror the split
`BillPositionsPromptBuilder` uses, so the caller builds an
`Llm::PromptPayload` the same way for both: `#system_prompt` is
bill-independent and cache-eligible, while `#user_message` carries the
per-call document list and is not. This class deliberately has no
single-string `#call` method (the shape `BillPositionsPromptBuilder` and
`BillSummaryPromptBuilder` use for their llama.cpp path) — it only ever
reaches Claude, which takes the system/user split directly.

The model's required answer shape lives in
`config/schemas/testimony_classification.json`.

## How much of a document's text the model sees

`MAX_DOCUMENT_CHARS` (2,000) is derived from measurement, not chosen:
`rake sway:measure:classification_corpus` over `legislation/bills/hearings/`
found that 90% of documents
state their position within 813 characters, so 2,000 sends most undecided
documents in full while bounding the tail's cost. Re-run the task after any
`Testimony::NameRules` change — the figures move with it.

Raising the bound to the worst observed offset would multiply prompt size
~4.6x to catch the remaining ~2% of documents, for which the model still
sees the name, a failed call falls open to "keep", and a wrong verdict
stays correctable by bumping `PROMPT_VERSION` — not judged worth it.
`#sanitize_text` marks the cut point (`TEXT_TRUNCATION_NOTICE`) rather than
truncating silently, so the model knows it's reading an opening, not a
whole document.

`MAX_NAME_CHARS` (300) bounds a hostile or degenerate name so it can't blow
out the prompt — far above any real Legistar attachment name observed.

## How `#user_message` lays out the document list

The numbered document list is enclosed in an untrusted-text block
whose 16-hex delimiter suffix is unguessable from any prior
prompt; `#wrap` also neutralizes fences and registered boundary prefixes
carried inside. That per-call content is deliberately NOT cache-eligible,
unlike `#system_prompt`.

Each document occupies two lines, both index-prefixed, so a
surviving entry can't be mistaken for another document's. Collapsing
whitespace in the text happens right here — unlike in
`BillPositionsPromptBuilder`, where the document is its own structured
section — because a list item's line structure carries nothing the
classifier needs.
