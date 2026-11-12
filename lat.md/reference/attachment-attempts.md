---
lat:
  mode: reference
---
# Attachment download attempts

Attachment download attempts are recorded append-only in PipelineActivityLog without altering the testimony_attachments publish gate.

- Every attempt in `FetchHearingsService#download_attachments!` logs an entry to `PipelineActivityLogEntry`, including successes, budget exhaustion, missing URLs, rejections, transport errors, non-2xx responses, invalid magic bytes, and file write failures.
- `testimony_attachments` on `BillLlmProvisioning` remains the single authority on stored testimony; attempt history is append-only and no publish gate reads it.
- Each attempt log records `bill_external_id`, `sway_locale_id`, `attachment_id`, `filename`, `url`, `status`, `outcome`, `error`, and `created_at`.
- Reusing `PipelineActivityLogEntry` avoids a parallel logging store and inherits existing retention sweeps (`PipelineActivityLogCleanupJob`).
- Writers swallow logging failures so operational logging never interrupts or fails the attachment download loop.
- Evidence: `app/services/fetch_hearings_service.rb`, `app/models/pipeline_activity_log_entry.rb`, `app/services/pipeline_activity_logger.rb`, and `spec/services/fetch_hearings_service_spec.rb`.

## Later retry selection rules

Selection criteria governing when a failed attachment attempt recorded in PipelineActivityLog qualifies for scheduled re-download.

- Candidate scope: `RetryFailedAttachmentsJob` loads all retained `PipelineActivityLogEntry` records where `event_type = 'attachment_download_attempt'`, groups by `[bill_external_id, attachment_id]`, and requires the first attempt in the group to fall within `LOOKBACK_WINDOW` (14 days).
- Retryable outcomes: candidate qualifies if its most recent attempt failed with transient status `skipped_time_budget`, transport error (`Faraday::Error`, timeouts, connection failures), timeout ceiling (`Legistar::AttachmentFetch::TooSlow`), HTTP 429/5xx, or disk write failure (`write failed:`).
- Permanent rejections: candidate is excluded if its most recent attempt failed due to host allowlist rejection (`Legistar::AttachmentFetch::Rejected`), redirect loop (`too many redirects`), missing URL (`attachment has no download url`), non-PDF magic bytes (`response body is not a PDF (magic-byte check failed)`), HTTP 4xx (except 429), or size limit (`TooLarge`).
- Wait window: candidate is excluded if its most recent attempt occurred within `WAIT_WINDOW` (24 hours).
- Attempt limit: candidate is excluded if total retained attempts for the attachment across the retention window reach `MAX_ATTEMPTS` (3 attempts).
- Authoritative mirror: successful retry writes to `BillLlmProvisioning#testimony_attachments` and disk solely through `FetchHearingsService#persist_testimony!`.
- Unknown error handling: unclassified or unrecognized errors are refused and logged rather than retried.
- Evidence: `app/jobs/retry_failed_attachments_job.rb`, `sig/jobs/retry_failed_attachments_job.rbs`, `spec/jobs/retry_failed_attachments_job_spec.rb`, and `config/recurring.yml`.

## Retention sweep

Scheduled pruning of aged attachment download attempt records from PipelineActivityLogEntry.

- Retention window: `TrimAttachmentAttemptsJob` deletes records older than `RETENTION_DAYS` (30 days), which strictly exceeds `RetryFailedAttachmentsJob`'s 14-day `LOOKBACK_WINDOW`.
- Lookback safety margin: The 30-day window ensures attempts remain queryable throughout the 14-day retry eligibility window plus an additional 16-day audit buffer before deletion, guaranteeing no candidate is trimmed while eligible for retry.
- Batched deletion: Records matching `event_type = 'attachment_download_attempt'` and `created_at < 30.days.ago` are removed in batches of `BATCH_SIZE` (500) to minimize SQLite WAL write lock contention.
- Authoritative isolation: Trimming only deletes attempt history logs; `testimony_attachments` on `BillLlmProvisioning` is never modified or pruned by the sweep.
- Evidence: `app/jobs/trim_attachment_attempts_job.rb`, `sig/jobs/trim_attachment_attempts_job.rbs`, `spec/jobs/trim_attachment_attempts_job_spec.rb`, and `config/recurring.yml`.
