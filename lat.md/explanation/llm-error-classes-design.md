---
lat:
  mode: explanation
---

# Why Llm::TransportError and Llm::SchemaError are two classes

See [[docs/reference/llm-adapter-error-classification.md|llm-adapter-error-classification.md]] for the exact classification table both adapters must agree on. This document covers why each class exists and what happens to it downstream.

## Llm::TransportError

Raised by the LLM adapters when a call fails for a temporary reason: a timeout, a refused connection, a 429 rate-limit, a 401, or a 5xx.

`GenerateBillSummaryJob` re-raises this as `TransientBillSummaryError` so the job retries it (Solid Queue's polynomially-longer backoff, 3 attempts) — these failures usually clear with a retry.

## Llm::SchemaError

Raised by the LLM adapters when the model's answer is unusable: not valid JSON, or it parses but fails `BILL_SUMMARY_SCHEMA`. `GenerateBillSummaryJob` re-raises this as `DeterministicBillSummaryError`.

The job throws the work away instead of retrying (Solid Queue's `discard_on`) — the same bad answer comes back every time, so a retry only spends API budget on a guaranteed second failure.

## Why both message prefixes exist even though nothing parses them

`TransportError`'s message starts with `"claude transport:"` or `"llama.cpp transport:"`, and `SchemaError`'s carries a similar prefix, only so logs are easy to grep.

No code reads that prefix today — `PipelineActivityLogger` has no classifier matching on it (checked by grepping `app/` and `lib/`).
