---
mode: explanation
summary: "Why the Sentry gems must load in every environment, not just production, and how spec/lib/sentry_reporting_never_raises_spec.rb guards the fix."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why the Sentry gems load outside production too

Reporting an error must never become a second, worse error. The Sentry
gems used to be scoped to the production Gemfile group, so any rescue
block that called `Sentry.capture_exception` outside production raised
`NameError` the moment it ran — `Sentry` was not even defined.

The gems now load everywhere. `spec/lib/sentry_reporting_never_raises_spec.rb`
pins that a `Gemfile` tidy-up that scopes them back to production fails in
this spec rather than in a job log later.

The spec also lists every call site the original bug was found in
(`app/jobs/reconcile_user_districts_job.rb` and seven others) so moving one,
or dropping its `Sentry.` report, is noticed here rather than discovered the
same way the original bug was.
