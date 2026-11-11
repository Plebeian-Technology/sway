---
lat:
  mode: explanation
---

# Why GenerateBillSummaryJob's retry policy is shaped this way

For the exact error-to-policy mapping and the retry timing numbers, see [[docs/reference/bill-summary-retry-policy.md|../reference/bill-summary-retry-policy.md]]. This document explains why the policy is split the way it is.

## Why a schema error is discarded rather than retried

A `Llm::SchemaError` means the model's response broke the expected schema.

The same input would fail the same way again — retrying buys nothing and only burns API budget. That is why `DeterministicBillSummaryError` is `discard_on` rather than `retry_on`.

A `Llm::TransportError`, by contrast, is a network-style blip: the same call might succeed on a second try, so it is worth retrying with backoff.

## Why the retry window is about 20 minutes

`GenerateBillSummaryJob` is a background job an admin kicks off — it is not on a user-blocking path.

Upstream Anthropic outages routinely take 5 to 15 minutes to clear, so a shorter retry window would give up before the outage was over and force the admin to manually re-enqueue the job. The roughly-20-minute window (2 SDK retries per call, nested inside 3 job attempts with `:polynomially_longer` backoff) was chosen to comfortably outlast that.

**If a user-blocking surface ever reuses this job or its retry policy, tighten `attempts:`/`max_retries:`** — a user waiting on a response should not wait 20 minutes for a job to give up.

## Why the catch-all rescue wraps as transient

`GenerateBillSummaryJob#perform`'s outermost `rescue => e` catches any adapter error outside the `Llm::*` hierarchy and wraps it as `TransientBillSummaryError` rather than letting it escape unwrapped.

An unexpected (non-`Llm::*`) adapter error would otherwise leave the provisioning row stuck in `generating` with no stored message and no retry handle — wrapping it as transient means `retry_on` still applies, giving the run a chance to recover from what might be a one-off fault rather than stranding the row.
