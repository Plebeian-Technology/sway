---
lat:
  mode: explanation
---

# Why spec/config/recurring_spec.rb checks registration, not just shape

Explains why spec/config/recurring_spec.rb checks solid_queue task registration directly instead of only the YAML shape, and why specific tasks each get their own presence guard.

## Why every entry is checked against solid_queue's own registration rule

`solid_queue` registers a recurring task only when its YAML entry has a `schedule:` key (`configuration.rb:174` — `if options&.has_key?(:schedule)`).

No version of `solid_queue` understands a `cron:` key; an entry keyed with `cron:` is dropped without a word and never runs.

`"every entry registers with solid_queue"` checks registration itself, which older string-comparison specs never did: every entry, in every environment, has to get past the gem's own check and build a working `RecurringTask` — which also proves the schedule parses, the job class exists, and a next run time can be worked out. Because the test environment never loads the `solid_queue` schema into the queue database, the spec repeats the two checks `RecurringTask` runs on itself (schedule supported, job class exists) without building the ActiveRecord model.

The registration filter is exercised a second time, directly, in `"survives solid_queue's has_key?(:schedule) registration filter"`: it runs the exact filter `SolidQueue::Configuration#recurring_tasks` applies (`... if options&.has_key?(:schedule)`) over the config loaded the same way `solid_queue` loads it (`ActiveSupport::ConfigurationFile.parse`, then `deep_symbolize_keys`). An entry keyed with `cron:` has no `:schedule` key, so the filter drops it and it never registers — this check fails on the old `cron:` config and passes once the key is `schedule:`. The daily and weekly org-digest dispatchers were the tasks actually found declared with `cron:`, which `solid_queue` 1.4.0 silently ignored — the digest jobs never ran, and `PendingOrgDigestEntry` rows piled up forever with no error anywhere.

## Why specific tasks get their own "is registered" guard, not just the generic checks

The generic examples above check that every entry which EXISTS is well formed; nothing in them checks that a PARTICULAR entry exists at all.

Two recurring tasks get their own dedicated presence guard because losing the entry — a merge conflict resolved the wrong way, a YAML edit made during a deploy change — would leave the suite green with no other signal:

- `reclaim_abandoned_summary_runs` is the only server-side
  enforcement that a stranded bill-summary row gets an exit (see
  `docs/explanation/abandoned-run-reclaim.md`). `spec/jobs/reclaim_abandoned_summary_runs_job_spec.rb`
  calls `described_class.new.perform` directly, so it proves only that the
  job works IF something runs it — it says nothing about whether anything
  actually does.
- `reclaim_abandoned_pipeline_runs` (see
  `docs/explanation/reclaim-abandoned-pipeline-runs-job-design.md`) carries
  the same argument: its job spec proves the sweep works if something runs
  it. Losing this `recurring.yml` entry puts the stuck Run button back,
  with the suite still green.
