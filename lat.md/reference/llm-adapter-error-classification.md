---
lat:
  mode: reference
---

# LLM adapter error classification

`Llm::ClaudeAdapter` and `Llm::LlamacppAdapter` are two implementations of the same agreement.

- `Llm::ClaudeAdapter` and `Llm::LlamacppAdapter` are two implementations of the same agreement: each must classify a failed structured-output call the same way, because callers such as `GenerateBillSummaryJob` decide whether to retry based on the raised class, not the provider. See llm-adapter-shared-contract-drift.md for why this is enforced with a single shared RSpec example (`spec/support/shared_examples/llm_structured_output_adapter.rb`) rather than duplicated per-adapter spec code.

## The clauses

Classification mapping associating upstream LLM failure modes with internal exception types and retry policies.

| Condition | Raised as | Job behavior | Why |
| --- | --- | --- | --- |
| Truncated response | `Llm::SchemaError` | Discarded | Hitting the token cap fails the same way every time, so a retry pays again for a guaranteed repeat. |
| Blank body | `Llm::TransportError` | Retried | A blank body can be passing network noise, and the same prompt may well succeed next time. |
| Transport failure | `Llm::TransportError` | Retried | |

- The blank-body clause is the one that drifted once: without stripping whitespace, a body of `"\n"` reaches `JSON.parse`, comes back a schema error, and is discarded — the opposite answer to the same input from the two adapters.

- For how a job-level wrapper on top of these two exception classes maps to Rails' `retry_on`/`discard_on` and the resulting retry timing, see [[docs/reference/bill-summary-retry-policy.md|../reference/bill-summary-retry-policy.md]].

## Helper API the host spec supplies

`RSpec.shared_examples "an Llm structured-output adapter"` stays provider-free by requiring the including spec to define four helpers:

| Helper | Purpose |
| --- | --- |
| `#stub_adapter_body(body)` | Make the client double answer with that raw body. |
| `#stub_adapter_truncated` | Make it answer a body the provider flagged cut off. |
| `#stub_adapter_transport` | Make it raise the provider's own transport error. |
| `#run_structured_call` | Run one structured-output call through the adapter. |
