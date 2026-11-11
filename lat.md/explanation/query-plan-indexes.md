# Index shapes the query planner can use

SQLite reads at most one index per table for a query. An index whose columns are in the order a query asks for them answers both the filter and the sort; one in any other order answers the filter and then sorts the rows again.

`EXPLAIN QUERY PLAN` names which of the two happened. `SEARCH <table> USING
INDEX <name>` is an index read; `USE TEMP B-TREE FOR ORDER BY` is a throwaway
sort structure built for that one query; `SCAN <table>` is every row.

## Bill of the month reads by locale then date

`Bill.of_the_month` filters on `sway_locale_id` and orders by
`scheduled_release_date_utc` descending, which is the reverse of the column
order in the unique index the table already carried.

That unique index — `index_bills_on_scheduled_release_date_utc_and_sway_locale_id`
— leads with the ordering column and follows with the equality column, and its
column order is what its uniqueness constraint means, so reordering it would
change the constraint. `index_bills_on_locale_and_release_date` is a second,
non-unique index with the columns the other way round. Both queries in
`Bill.of_the_month` then read an index and take their order from it.

The write cost is a few hundred rows created by administrators and by the
pipeline, against a read path that is the third most requested action in the
application.

## The activity log's errors-only filter

The Bill Creator's activity log can be filtered to errors, which selects on
`severity` and orders by `created_at` descending. The table carried a
single-column index on each column, and SQLite reads one index per query.

`index_activity_log_severity_and_created_at` carries both, equality column
first and ordering column second, and replaces the single-column severity
index rather than joining it. The table is insert-only, so that trades one
index write for another.

One line of the plan survives the change. `PipelineActivityLogEntry.recent_first`
orders by `created_at` descending and then `id` descending, and the index holds
no `id` column, so the plan still reports `USE TEMP B-TREE FOR LAST TERM OF
ORDER BY` — a sort of the rows sharing a timestamp, rather than of every row
the filter matched.

## Single-column indexes a composite already covers

SQLite answers a query on the first column of a two-column index from that
index, so a separate single-column index on the same column adds nothing a
reader can use and one more structure every insert and update maintains.

Ten such indexes were dropped, each the leading column of a unique composite
on the same table. Two of them sat on the hottest write paths in the
application: `user_votes` is written on every vote cast, and
`bill_score_districts` is rewritten whenever a score is recomputed. SQLite
allows one writer at a time, so the removed writes were paid for serially by
everything else waiting to write.

The organizations page's following filter reads `organization_follows` by
`user_id` alone, which is the case where the loss would show. It reads
`idx_organization_follows_on_user_and_organization` instead, and the plan
still reports a search rather than a scan.

Legislator votes are the exception: their current uniqueness indexes are partial, so a bill-only lookup cannot use either leading column without a matching predicate. [[db/migrate/20261005000000_add_bill_lookup_index_to_legislator_votes.rb|A dedicated bill lookup index]] covers that read while preserving both uniqueness constraints. It also applies to databases built from migration history, which still have the older person-keyed composite rather than the current term-keyed partial indexes.

## A query-cost guard measures growth, not a ceiling

A guard against a per-row query runs the same page at two sizes and compares the counts, rather than asserting that the page stays under a fixed number.

What matters is whether the cost grows with the collection, and a ceiling has to
be re-guessed every time an unrelated query is added, so it decays into a number
nobody trusts. The costs being guarded are real: reading an organization's
mirrored icon was 200 extra reads on a full page, on one Raspberry Pi over
SQLite, and a prop rebuilt on every render of a tab that polls every few seconds
pays its cost again on each tick.

The same two-size comparison can track complete response-body bytes alongside query counts. A short response has to contain bytes, and a roster test also checks that the short serialized roster has eligible rows because the surrounding HTML or JSON keeps an empty roster response nonzero. Response size is a relative comparison, not a fixed threshold.

The mirrored-asset measurement subscribes to `sql.active_record` with `|*, payload|`, matching the subscriber block shape used elsewhere in the specs. Naming the positionals before `payload` gives it the narrower block type from the RBS overlay, where it can be inferred as nil; the rest capture leaves `payload` usable for SQL and query-name inspection.

The Bill Creator icon example measures its own organization list, separate from the bill page's list. [[app/controllers/bills_controller.rb#BillsController#set_bill]] preloads legislator votes, the bill's legislator, locale, and LLM provisioning, but not organization icons. The history example grows the inactive representative links because the tab contains each person a user stopped being represented by. Every past legislator needs a term because the history serializer otherwise drops that row and its portrait read; the short positive-read guard would then catch a vacuous measurement.

The bill detail response measures complete bytes at two eligible roster sizes. Its initial browser response leaves the optional legislator roster, vote list, and districts out, while the default bearer response still resolves optional props; separate correlated vote fixtures ensure the browser size check can detect votes becoming eager again. The mobile omission-header measurement separately proves that omitting the roster keeps bearer JSON size flat as that roster grows.

[[app/serializers/bill_page_resource.rb#BillPageResource]] preloads score district rows and their districts before [[app/serializers/bill_score_resource.rb#BillScoreResource]] serializes the score. [[app/serializers/bill_score_district_resource.rb#BillScoreDistrictResource]] uses [[app/serializers/bill_page_district_resource.rb#BillPageDistrictResource]] for the nested district shape, so each scored district is already available to the resource. The cost spec checks query growth; [[spec/system/bill_score_charts_spec.rb]] verifies populated charts on both bill pages.

[[app/models/bill.rb#Bill#to_builder]] filters its already-loaded `categories` association in memory before emitting category names. `pluck` would issue a fresh query and bypass the [[app/controllers/bills_controller.rb#BillsController#index]] `.includes(:categories)` preload.

[[lib/sway/sql_query_telemetry.rb#SqlQueryTelemetry]] normalizes SQL literals into fingerprints and counts both total SQL executions and maximum per-fingerprint repeats across a block. [[app/controllers/application_controller.rb#ApplicationController#track_sql_query_telemetry]] uses the same measurement to attach query and repeat counts to Lograge request logs, expose a `Server-Timing` header to admins, and warn when a request repeats a SQL fingerprint at or above `Sway::SqlQueryTelemetry::N_PLUS_ONE_WARN_THRESHOLD`.

## Statistics the planner reads

SQLite chooses an index from measured statistics when a database has them and from built-in guesses when it does not. The development database held no `sqlite_stat1` table, so every plan was chosen on guesses.

Statistics live in the database file rather than in the schema, so `db/schema.rb`
does not carry them and a database built from it has none. The
`AnalyzePrimaryDatabase` migration writes them once on deploy, after the index
changes above, so they describe the indexes the application actually has, and
`AnalyzeDatabaseJob` rewrites them daily in development and production alike.

`ANALYZE` rather than `PRAGMA optimize`: the optimize pragma only considers
tables the connection running it has already queried, and a background job's
connection has queried none of them. `analysis_limit` caps the rows sampled per
index, which is what keeps a whole-database `ANALYZE` cheap.

The schema dumper cannot describe `sqlite_stat1` — its `idx` column has no
declared type — and wrote a "Could not dump table" comment into `db/schema.rb`
on the first dump taken from an analyzed database.
`config/initializers/schema_dumper_statistics.rb` adds the table to
`ActiveRecord::SchemaDumper.ignore_tables`, so a dump from any machine leaves
the same file.
