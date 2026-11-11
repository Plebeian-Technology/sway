---
mode: reference
summary: "Documents how GenerateBillSummaryJob maps LLM adapter failures to retry-with-backoff or discard-without-retry, and the resulting retry timing."
status: agent-extracted
related: []
---
# GenerateBillSummaryJob retry policy

<!-- vale Vale.Spelling = NO -->

`GenerateBillSummaryJob` wraps every LLM adapter failure into one of two
job-level errors, and each error class carries its own retry behavior.

## Error mapping

| Adapter error raised | Wrapped as | Retry behavior |
| --- | --- | --- |
| `Llm::TransportError` | `GenerateBillSummaryJob::TransientBillSummaryError` | Retried with backoff (`retry_on`) — a network-style blip. |
| `Llm::SchemaError` | `GenerateBillSummaryJob::DeterministicBillSummaryError` | Discarded, no retry (`discard_on`) — the model's response broke the expected schema. |

## Retry timing

`retry_on TransientBillSummaryError, wait: :polynomially_longer, attempts: 3`.

- Each adapter call is itself retried by the SDK up to 2 times before it
  raises `Llm::TransportError` to the job.
- The job then retries the whole `#perform` up to 3 times, with
  `:polynomially_longer` waits of roughly 3 seconds, 18 seconds, and 83
  seconds between attempts.
- Combined, a failing job can sit "running" for about 20 minutes before it
  finally gives up.

See also: [../explanation/bill-summary-retry-policy.md](../explanation/bill-summary-retry-policy.md)
for why these numbers were chosen.
