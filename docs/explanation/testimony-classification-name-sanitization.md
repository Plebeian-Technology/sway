---
mode: explanation
summary: "The threat model behind ClassificationPromptBuilder#sanitize_name — why attachment names are treated as attacker-controlled and what order its defenses run in."
status: agent-extracted
related: [testimony-classification-prompt-design.md]
---

# Sanitizing attachment names for the classification prompt

`Testimony::ClassificationPromptBuilder#sanitize_name` treats an attachment's
file name as operator-typed free text from a third-party system — data, not
instructions. It likely traces back to a submitter's own filename, mediated
only by an optional clerk rename (see
`spec/services/legistar/attachment_url_spec.rb`), so the builder
treats it as plausibly attacker-controlled.

## A second control, not a duplicate one

`#user_message` already encloses the whole document list in an untrusted-text
block. `#sanitize_name` is a second, independent control: the
enclosure stops a name from asserting the prompt/data boundary in prose (for
example, claiming to be an instruction), while `#sanitize_name` stops a name
from forging the list's line structure itself — turning one document's NAME
line into what looks like a second document.

## Why the steps run in this order

`#sanitize_name` calls `Llm::PromptLabel.collapse(name)` (which scrubs the
name to valid UTF-8 before collapsing whitespace), then
`Llm::UntrustedTextBlock.neutralize` on the result, then cuts the length to
`MAX_NAME_CHARS`:

1. **The UTF-8 scrub inside `.collapse` has to run before the cut.**
   `.collapse` and `.neutralize` can both raise on invalid UTF-8, and
   `Testimony::AttachmentClassifier#llm_verdicts` rescues at the whole-batch
   level. Cutting the length before scrubbing would still leave a bad byte
   inside the kept slice, failing the entire batch to "keep everything"
   instead of just the one bad document.
2. **The length cut runs AFTER `.neutralize`.** `.neutralize` (via
   `Llm::UntrustedTextBlock`'s `#wrap`) can lengthen a registered prefix it
   finds inside the text. Cutting the name to `MAX_NAME_CHARS` before
   neutralizing would not actually bound what ends up in the prompt.

`#sanitize_text`, used for the document's extracted body text, applies the
same scrub/collapse/cut treatment, but over a channel with a different risk
profile: a PDF body a member of the public uploaded, rather than a
clerk-accepted filename. It is both less trustworthy and higher-stakes — a
successful steer there could delete real testimony or admit bill text into
the positions prompt — which is why its truncation is announced
in the prompt rather than silent: an unmarked cutoff could read as a real
signal (a letter with no signature) instead of an artifact of truncation.
