# Bill session archiving

Session rollover archives unfeatured bills within one locale while preserving their records, votes and scores. The operator procedure is [[archive-previous-session-bills]].

## Eligibility

[[app/services/archive_previous_session_bills_service.rb#ArchivePreviousSessionBillsService#candidates]] selects unarchived, unscheduled bills belonging to completed sessions in the requested locale.

The boundary is the locale's latest active session, which must already have started. An assigned bill qualifies when its session is inactive, began earlier and ends on or before that boundary. Shared transition dates occur in Congress and Baltimore's configured sessions. An unassigned legacy bill qualifies only when its introduction precedes the new session's first day. Future introductions, overlapping sessions and other active sessions remain excluded.

## Why Bills of the Month are never archived

Every nonempty release date protects a Bill of the Month selection, including past and future dates, so featured bills remain interactive even when their legislative session is inactive.

## Preserved history

[[app/services/archive_previous_session_bills_service.rb#ArchivePreviousSessionBillsService#call]] stamps eligible rows in one transaction without deleting bills or dependent records.

The timestamp makes repeat runs skip archived bills. Votes, scores, summaries, campaigns and cached files remain stored. Future calculations using bill joins exclude archives, so retaining score rows does not freeze future aggregates. Archiving is an explicit maintenance operation after session configuration is synchronized; seeding does not silently archive rows.

## Active views

[[app/models/bill.rb]] applies archive exclusion to all ordinary bill queries, including associations, identifier lookups, reloads, updates and deletes.

Default public lists and admin Bill Creator routes exclude archived bills, and admin edit or mutation requests for an archived bill return a missing-record response. Selecting an inactive historical session on `/bills` ([[app/models/bill.rb#Bill#for_legislative_session]]) or opening a bill detail page ([[app/controllers/bills_controller.rb#BillsController#show]]) explicitly unscopes `archived_at` for read-only inspection, preserving a reader's previously recorded vote on that bill while disabling new votes and legislator outreach. Standalone organization positions, pending changes, summary reports, `UserVotesController` endpoints and partner articles use inner bill joins before returning rows, and casting a vote on an archived bill remains rejected.

## Stale records

[[app/models/bill.rb#Bill#require_visible_record]] rejects updates and destruction when a previously loaded bill has since been archived.

The destruction guard runs before dependent callbacks inside the transaction, preserving associated history even when the parent DELETE would affect no rows. SQLite immediate transactions serialize the guard with the archive operation. Stale scheduling fails rather than reporting a successful selection or clearing the archive timestamp.

## Pipeline and archive exclusion

[[app/services/pipeline_locale_lock.rb#PipelineLocaleLock]] prevents archive application and pipeline execution from overlapping within the same locale.

[[app/services/archive_previous_session_bills_service.rb#ArchivePreviousSessionBillsService#call]] refuses immediately when the locale lock is held or a pipeline remains active, including one awaiting summary batch results. Preview remains read-only. Queued jobs wait behind an archive application; other locales remain independent.

[[app/jobs/run_legislation_pipeline_job.rb#RunLegislationPipelineJob#perform]] and [[app/services/summary_batch_ingest.rb#SummaryBatchIngest#call]] hold the same lock throughout their execution. The job rereads the run after acquiring the lock so a stop during its wait remains effective. Stopping a run does not release its worker's lock before that work exits. A run with no resolved locale holds a global lock because its jurisdiction is unknown.

Lock files sit beside the primary database on storage shared by the web, jobs and maintenance containers. They remain on disk so every process locks the same inode; closing the file or process exit releases ownership. No database write transaction stays open across pipeline network or model calls.

## Ingestion and pending work

[[app/services/legislation_ingestion_service.rb#LegislationIngestionService#archived_identity?]] checks retained identity existence without returning an archived Bill object.

A repeated upstream identity is skipped, leaving its metadata and archive timestamp intact. [[app/services/fetch_bills_service.rb#FetchBillsService#seed_ar_rows]] creates pipeline rows only for accepted ingestion results. [[app/services/summary_batch_ingest.rb#SummaryBatchIngest#answers_for]] joins visible bills so archived batch answers cannot block live siblings or write new summaries.

Supported ingestion reaches [[app/services/legislation_ingestion_service.rb#LegislationIngestionService#upsert_bill_payload]] through fetch seeding within the worker's locale lock. The initial archive check remains necessary for historical upstream identities; live-row uniqueness recovery uses the winning visible row without repeating that check because archive application cannot intervene under the lock. Independently invoked ingestion racing archive maintenance is outside this contract.

The initial visible-bill join determines readback eligibility. [[app/services/summary_batch_ingest.rb#SummaryBatchIngest#call]] holds the locale lock throughout result persistence, retry selection and settlement, so supported archive application cannot change visibility during readback. Repeated bill-by-id existence probes add queries without extending that guarantee. Concurrent physical bill deletion during readback is outside the operating contract; the locale lock excludes archive maintenance, not ordinary deletion.

[[app/jobs/run_legislation_pipeline_job.rb#RunLegislationPipelineJob#run_bill_level_stage]] traverses visible bills without retained-archive identity probes. The shared locale lock excludes archive application during execution. Historical queued or resumed runs crossing session rollover are outside the operating contract; default-scoped lookup retains ordinary missing and ambiguous identity failures.

[[app/models/user_legislator_email.rb#UserLegislatorEmail#sendable?]], [[app/services/score_updater_service.rb#ScoreUpdaterService#call]] and [[app/jobs/notify_organization_followers_job.rb#NotifyOrganizationFollowersJob#perform]] check bill visibility before performing queued work. Retained vote, position and outreach records do not imply that an archived bill remains actionable.
