---
lat:
  mode: explanation
---

# Why ApplicationJob discards ActiveJob::DeserializationError

Jobs that take an ActiveRecord object as their argument exist only to act on that record (score recomputes, the outgoing legislator email).

Real deletion paths remove the record between enqueue and perform — the daily `OnDeactivatedPhoneDeleteUserJob` cascade, a legislator reseed — leaving the job holding a GlobalID that no longer points at anything.

`ApplicationJob` discards the job in that case: the work is meaningless once the record is gone, and re-raising would only recycle the failed set forever.

Newer jobs pass plain ids instead (`GenerateBillSummaryJob` and friends) and handle the missing record explicitly — prefer that for new jobs.
