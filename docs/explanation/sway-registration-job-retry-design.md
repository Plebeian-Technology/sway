---
mode: explanation
summary: "Why SwayRegistrationJob marks a user failed only after retries are exhausted, and why the rescue re-raises transient errors without marking failure itself."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `SwayRegistrationJob` separates transient retry from permanent failure

The upstream geocoding / legislator-roster lookups are network calls that
hiccup now and then. `TRANSIENT_ERRORS` lists the classes worth retrying
with backoff instead of permanently failing the user's registration on the
first blip. `SwayGeocode::ServiceUnavailableError` is the service's own
wrapper for an OpenStates/Census outage (its docstring already declares it
retryable), so it is deliberately included even though it is not a plain
network error class.

## Why the user is marked failed only after retries are exhausted

The `retry_on` block runs ONLY once retries are exhausted — the user is
marked failed after all attempts are spent, not on attempt 1.

## Why the rescue re-raises transient errors without marking failure

This is load-bearing: the rescue lets `retry_on` own the transient
classes — it re-raises WITHOUT marking the user failed, so they stay
`:processing` across retries. The `retry_on` block marks failed only after
attempts are exhausted. Without this re-raise, the user would be marked
failed on attempt 1.

## Why `mark_failed_if_processing` uses `find_by`, not `find`

`find_by`, not `find` — a user deleted mid-run must not raise
`RecordNotFound` inside the rescue and hide the original error.
