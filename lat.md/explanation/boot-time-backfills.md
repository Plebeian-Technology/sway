---
lat:
  mode: explanation
---

# Boot-time backfills

Two one-off cleanup jobs are queued from initializers as the application starts, rather than from the recurring schedule. Each one fills a column that older rows were written without.

`config/initializers/backfill_bill_categories.rb` and
`config/initializers/backfill_bill_interesting_scores.rb` hold the same block of
code with two job names in it. `BackfillBillCategoriesJob` gives summarized
bills their missing categories and `BackfillBillInterestingScoresJob` fills missing
interesting scores.

## Why boot rather than the recurring schedule

Both have an end: once every affected row is fixed there is no work left in it, and new unfixed rows arrive with a deploy that adds a column rather than between deploys.

An entry in `config/recurring.yml` would run the job at a fixed interval
forever, long after the last row was fixed. A boot enqueue runs it once per
deploy instead, which is the rate at which the rows it looks for can appear. The
cost of an unnecessary run is one indexed query that matches nothing, so a
deploy with nothing to fix pays almost nothing.

Removing an initializer once production holds no more affected rows is the
intended end state for each of the two.

## Only the web server process enqueues

`Sway::BootEnqueue.web_server_process?` is true only in a `bin/rails server` process, and each of the two initializers stops unless it is true.

`rails/commands/server/server_command.rb` defines `Rails::Server` before
`config/environment` is loaded, so that constant exists inside
`after_initialize` for the web server and for nothing else — console, `runner`,
rake and `bin/jobs` all leave it undefined. Kamal starts the container with
`bin/rails server` (`bin/docker-entrypoint`), so the production web containers
are the processes that enqueue.

### Why the Rake constant was the wrong test

These initializers carried `next if defined?(Rails::Console) || defined?(Rake)`, and that guard skipped the enqueue in every process, the web server included.

`defined?(Rake)` is true whenever anything in the process has loaded Rake, and
in this application that is every process: `dip run rails runner 'puts
defined?(Rake).inspect'` prints `"constant"`. None of the three jobs was ever
queued. The queue database never held a `Backfill*` row, even where every recurring
job was present.

A test on `Rake.application.top_level_tasks` separates a running task from a
loaded gem, but it states the rule as a list of processes to exclude, and that
list grows with every new entrypoint. Naming the one process that should enqueue
is the smaller statement.

## A second enqueue is discarded

Each of the two jobs declares `limits_concurrency to: 1, on_conflict: :discard` under a fixed key, so a duplicate enqueue is dropped rather than queued behind the first.

Production runs two web containers and both boot the same initializers, so every
deploy produces two enqueues per job. The concurrency limit folds each pair into
one run. The jobs are written to be safe when they do run twice in any case:
each opens with a query that matches nothing once its backfill is complete and
returns before doing anything else.

## Why a stamped bill costs nothing on the next boot

The category backfill selects bills whose stamp is older than the summary it judged, so a bill already stamped against its current text is skipped on every later boot.

The comparison runs both ways for a reason. A stamp older than the summary means
the categories were decided from text that has since changed, and the bill is
re-read; a stamp newer than the summary still describes the text on the row, so
the boot buys nothing by re-reading it. The saving is the whole point of keeping
the stamp rather than a boolean.

### The category backfill buys only a missing active verdict

[[app/jobs/backfill_bill_categories_job.rb#BackfillBillCategoriesJob|The backfill]] categorizes stored summaries without summarizing again, so inactive categories do not exclude a bill from the active taxonomy pass.

An explicit failed summary is excluded, while legacy unset statuses remain
eligible. An empty active taxonomy stops before adapter construction; the active
names are loaded once in stable order. A freeform taxonomy mismatch leaves a
useful summary completed and eligible for the constrained category pass. Only
the assigner's deterministic no-match receives the stamp described above; an
adapter schema failure remains eligible on a later boot. A broad per-bill rescue
contains validation races and continues with later bills. Programming errors are
also contained, but their exception and bill identity remain logged. A no-match
warning exposes a taxonomy gap rather than silently exhausting the bill's eligibility.

## A failed enqueue is logged and left for the next boot

The enqueue sits under a rescue that names four errors, because a fresh container's queue database connection may not be ready when the initializer runs, and a boot must not end on a queue that is not up yet.

The four are `ActiveRecord::ConnectionNotEstablished`,
`ActiveRecord::NoDatabaseError`, `ActiveRecord::StatementInvalid` and
`SolidQueue::Job::EnqueueError`. The last is in the list because a queue
database that has not been migrated raises its missing-table error wrapped in
that class rather than as a plain `StatementInvalid`. A bare `rescue` would
cover all four and also hide a real error at boot, which is why the four are
written out.

Nothing retries inside the process. The next boot of a web container runs the
same initializer again.
