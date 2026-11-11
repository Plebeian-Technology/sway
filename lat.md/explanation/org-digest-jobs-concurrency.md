---
lat:
  mode: explanation
---

# Why the org digest jobs limit concurrency to one run

`DailyOrgDigestJob` and `WeeklyOrgDigestJob` each allow at most ONE run at a time (`limits_concurrency to: 1`).

This stops the scheduled run (23:00 UTC daily, or Sunday 23:00 UTC weekly, both via `config/recurring.yml`) and a manual admin trigger from overlapping — each would otherwise read the full pending-row set before either claimed it, and the same billable SMS would go out twice. A second concurrent enqueue is discarded (the run already in progress covers it).
