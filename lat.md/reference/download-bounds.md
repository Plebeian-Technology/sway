---
lat:
  mode: reference
---
# Download bounds

Attachment limits must constrain received bytes and elapsed download time while the response is arriving.

- A limit checked after `response.body` has been read does not bound download memory, and idle socket read timeouts do not bound slow dribbling downloads.
- The streaming callback must enforce received-byte limits (`MAX_ATTACHMENT_BYTES = 32.megabytes`), preserve HTTP-status handling, and avoid accumulating a failed or retried body.
- Attachment downloads enforce a 30-second elapsed ceiling across the redirect walk, checked around the redirect loop and inside the chunk callback.
- Hearing attachment downloads use 2 attempts (1 retry via `max: 1`), cutting worst-case stalled download elapsed time across the 4-hop redirect walk from ~494s to ~247s within the 15-minute bill budget.
- Bill discovery and bill-PDF fetching in `FetchBillsService` retain 4 attempts (3 retries via `LEGISTAR_DEFAULTS`, `max: 3`) for resilience, ensuring non-attachment callers do not inherit the reduced retry ceiling.
- The retry divergence is compensated by [[attachment-attempts#Attachment download attempts#Later retry selection rules|RetryFailedAttachmentsJob]]: hearing attachments have an asynchronous scheduled retry mechanism (14-day lookback, 4-hour delay / 24-hour wait window) that pays for the lower immediate retry count, whereas bill discovery has no separate asynchronous recovery pass.
- Refusal errors for size and elapsed time are dedicated `StandardError` subclasses (not Faraday timeout or transport retry exceptions), translated to subclasses of `Legistar::AttachmentFetch::Rejected` so `faraday-retry` does not multiply the bound.
- Tests cover oversized streamed responses, slow dribbling responses spanning the redirect walk, retry refusal behavior, and call-count bounds proving attachment callers use 2 attempts while non-attachment callers retain 4.
- Evidence: `lib/sway/faraday_stack.rb`, `app/services/bounded_response_body.rb`, `app/services/legistar/attachment_fetch.rb`, `app/services/fetch_hearings_service.rb`, `app/services/fetch_bills_service.rb`, `app/jobs/retry_failed_attachments_job.rb`, and `app/services/fetch_law_corpus_service.rb`, with `spec/lib/sway/faraday_stack_spec.rb`, `spec/services/legistar/attachment_fetch_spec.rb`, `spec/services/fetch_hearings_service_spec.rb`, `spec/jobs/retry_failed_attachments_job_spec.rb`, and `spec/services/fetch_law_corpus_service_spec.rb`. Verify the current Faraday callback contract before changing the downloader.
