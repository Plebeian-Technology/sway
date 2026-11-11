---
lat:
  mode: explanation
---

# Why Llm::SchemaValidator is shared, and why every failure discards the job

`Llm::SchemaValidator` is shared by `ClaudeAdapter` and `LlamacppAdapter`: it parses the raw text a model returned as JSON, then checks it against `BILL_SUMMARY_SCHEMA` — a second line of defense even after structured output.

Putting it here removes about twenty duplicated lines while keeping error messages tagged by provider ("Malformed JSON from claude" vs "from llama.cpp"), which keeps `SwayLogging` output sortable.

Every failure raises `Llm::SchemaError`, so the job discards the work (`DeterministicBillSummaryError`) instead of retrying. A schema violation will happen again on retry, wasting API budget.

## Why the normalizer and checker cannot disagree

The request no longer carries keywords Anthropic calls unsupported (see `Llm::StructuredOutputSchema`), but this checker still enforces them. Fix what dropping surplus can fix; let the rest fail below.

The schema hash comes from the checker itself, not the caller. It used to be a `schema_hash:` argument both adapters filled with the CALLER's `schema:`, handing back a decision meant to stay theirs.

`JSONSchemer::Schema#value` is the exact hash the checker was built from, so the normalizer and checker now read one object by construction, and there is no argument left to get wrong.

## Why the schema-validation failure message is tagged with the provider too

Tagged with the provider, like the malformed-JSON branch. Both adapters promise these messages are grep-able by source — and this branch, the more common failure, was missing the tag before.
