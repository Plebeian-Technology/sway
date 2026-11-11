---
lat:
  mode: explanation
---

# Why pasted summaries are marked with one shared provider string

`OPERATOR_PASTE_PROVIDER` and `isOperatorPasted` (`app/frontend/components/admin/creator/llm-summary/provenance.ts`) are the browser's half of how Sway records where a bill summary's text came from.

## What the value means

When an operator pastes a summary in, `PasteSummaryService` stores `llm_provider: "operator_paste"` next to that text on the server, and clears the model name in the same write, since no model produced it.

Every other value `llm_provider` can hold is the name of an LLM provider.

## Why the difference matters

The difference is not decorative.

Pasted text was written by hand and is gone for good once a regenerate overwrites it, so this is the one case where the destructive regenerate action has to warn the operator before it runs — an LLM-generated summary can simply be regenerated again with no loss.

## Why it is spelled once, in one file

The string `"operator_paste"` is spelled once, in one file, because two hand-copied string comparisons is exactly how matching checks on the server and the browser can drift apart.

Both sides have to agree on the same string for the marker to mean what either side thinks it means.

## LlmSummaryProvenanceChip

Says that this text was written by a person, right on the screen that offers to overwrite it.

It appears for operator-pasted text ONLY. A model-generated summary needs no warning stamp: it can always be produced again by Regenerate, so overwriting it costs nothing an operator cannot get back. A hand-written one cannot — Regenerate on this card destroys it for good — which is the one fact this chip exists to put in front of that click.

## LlmSummaryRegenerateConfirmDialog's llmProvider prop

Where the text about to be replaced came from. A pasted summary was written by hand and cannot be recovered, so the operator has to be told BEFORE the click that destroys it, not find out from a server log afterwards.
