---
lat:
  mode: explanation
---
# The legislation pipeline

Bills do not arrive as bills. They arrive as Legistar records, hearing PDFs and law-corpus pages, and the pipeline turns those into a `Bill` row an admin can publish. It is a dependency graph of eight stages.

A run covers one bill or every bill in a locale, and an operator drives it from
the admin Bill Creator.

## The stage graph

Stage dependencies live in one constant, `Pipeline::STAGE_DEPS`, and
`Pipeline::StageDeps.transitive_closure` expands whatever an operator asked for
into everything that request needs.

The eight stages are `fetch-bills`, `fetch-law`, `extract-text`,
`parse-sections`, `generate-diffs`, `fetch-hearings`, `clean-testimony` and
`summarize-bill`.

Two stages have no prerequisites and start immediately: `fetch-bills` pulls the
legislative record, `fetch-law` pulls the existing statute. `generate-diffs`
depends on both branches converging, since a diff is meaningless without the
law it amends. `summarize-bill` sits at the bottom, depending on the diff and
on cleaned hearing testimony, because the summary is supposed to describe both
what a bill changes and who spoke about it.

Keeping the graph in one constant rather than in the orchestrator means an
operator selecting a single mid-graph stage cannot accidentally run it against
missing inputs.

### The diff a summary reads is the file, not the row

`generate-diffs` writes its result to two stores — JSON and Markdown files under `LEGISLATION_ROOT`, and a JSON mirror in `bill_llm_provisioning.diff_content` — and the two can hold different answers.

Only the file reaches a model. `BillSummaryPromptBuilder#source_text_section`
takes the on-disk Markdown that `#on_disk_diff_markdown` returns, falls back to
`bill.extracted_text`, and otherwise emits a stub saying no bill text is
available; `diff_content` appears nowhere in that path, and
`GenerateBillSummaryJob` sends what it returns. The same class does read the
row — `#sources` goes through `SummaryDiffFacts` — so the counts an operator
sees beside a summary come from one store while the text the model reads comes
from the other. `Pipeline::ArtifactPresence` reads the row too, and it is what
decides whether the stage looks finished.

Across the Baltimore bills the two stores disagree. A bill can carry a
`diff_content` row, so `generate-diffs` reads as complete, while it has no
on-disk artifact and its prompt falls back to extracted bill text. Rows report
`sections_modified` above zero — sections with status `markup_modified`, and
amendment operations of `source: "markup"` — where the older files report
`sections_modified` 0 and `total_operations` 0, with statuses `section_not_found`
and `referenced_only`. Where a bill holds both, they often disagree outright; the
rest agree only in reporting nothing.

No rendered before-and-after exists in either store. The Markdown
files contain no diff fence, and a row cannot carry one at all: `_diff_block` is
one of the helper keys `#strip_helper_keys` removes before the payload is
persisted, so `diff_content` holds counts and section statuses while the
rendered diff lives only in the Markdown file.

So `summarize-bill` still does not receive what the paragraph above says it
depends on, and a summary cannot state what the law becomes.
`Legislation::MarkupOps` and the `markup_modified` branches of
`GenerateDiffsService#build_section_payloads` are newer than every artifact on
disk, and `MarkdownRenderer` already renders their diff blocks, so the two
stores converge for a bill the next time `generate-diffs` runs over it.

The not-found statuses on disk are of the same age. That parse matched
Maryland General Assembly amendatory verbs against Baltimore bills, which mark
amendments typographically instead — capitals for added matter, brackets for
deleted; it split a citation at its first hyphen, producing `art_10__sec_18`
where the corpus key is `art_10__sec_10-18`; and its one-line citation pattern
could not see the multi-line `BY repealing and re-ordaining` header that names a
bill's authoritative target. [[legislation-pipeline#Typographic markup and declared target resolution]]
owns what replaced all three.

## Each upstream source gets its own connection profile

The HTTP stack is built from named profiles rather than one shared connection,
because the sources differ in what they need.

The corpus download from a code host answers with a redirect to a separate
download host, so that profile mounts redirect following; its timeout covers a
multi-megabyte archive over the production machine's link rather than an
ordinary API call. The open-data roster sources are read-only public APIs that
return rate-limit and server errors under load, so theirs carries the same
bounded retries the legislative-record profile uses. All of them are GET-only,
which is what makes retrying safe at all.

In `FetchBillsService#default_faraday_conn` and `FetchHearingsService#default_faraday_conn`, connection profiles resolve dynamically from the locale's declared rules (`legislation_rules` and `hearings_rules`): when `retrieval` specifies `congress_dot_gov` or `congress`, the stack selects `Sway::FaradayStack.congress_gov`; when `base_url` is declared, it instantiates `Sway::FaradayStack.build(base_url:)`. Legacy vendor fallbacks to `Sway::FaradayStack.legistar` are eradicated, causing the services to fail fast with `StageError` if connection rules omit a valid retrieval strategy.

This fail-fast discipline extends to dead discovery methods and legacy backfill modes: `discover_legistar_hearings` and `backfill_missing` are pruned from service classes, delegating all upstream provider logic strictly to generic adapters.



## Fail-fast on drift

`Pipeline::StageKeys` translates between hyphenated stage keys — used in URLs,
the database and the frontend — and internal Ruby symbols. Both directions
raise `KeyError` on anything unrecognised, so a mistyped stage name stops at
the boundary.

More unusually, the module runs two integrity checks at load time and refuses
to boot on either failure: it verifies that the key map round-trips, and that
its symbol set matches `RunLegislationPipelineJob::DAG_ORDER` exactly. Adding a
stage to one place and not the other is the natural mistake, and it would
otherwise surface as a stage that silently never runs.

## How a stage resolves its SwayLocale

`FetchLawService#resolve_sway_locale` and
`FetchBillsService#resolve_default_sway_locale` each resolve the jurisdiction the
pipeline is wired to, and each raises `StageError` on a miss.

The error class is the point. `RunLegislationPipelineJob` declares
`discard_on ActiveRecord::RecordNotFound`, so a `RecordNotFound` raised from
either lookup would drop the job and leave the run sitting in its current stage
with no failure handler attached. `run_run_level_stage` re-raises `StageError`
unchanged; the catch is the outer `rescue StageError, BillProcessingError` on
the job's own `perform`, which passes the error to `handle_run_failure` — that
marks the run failed and records a message an operator can read — and then
re-raises.

Both services resolve their fallback via `resolve_default_sway_locale`, which
queries `SwayLocale.resolve_by_computed_name` with
`LegislationIngestionService::DEFAULT_LOCALE_NAME`. The fallback goes through
`resolve_by_computed_name` rather than `find_by(name:)`, because the name is
composed in Ruby and is not a column ([[locale-name-is-derived]]): a database
lookup for it raises `SQLite3::SQLException: no such column: name`. The default
locale string is defined once, as
`LegislationIngestionService::DEFAULT_LOCALE_NAME`, so no second copy can drift
from it.

`FetchBillsService` resolves before its database-writing loop, so a missing row
fails the stage at once instead of surfacing later as a `RecordInvalid`.
`FetchBillsService#sway_locale_name` memoizes the same lookup, because `#persist`
runs once per bill and the answer cannot change inside a run.

`FetchLawService#call` and `#resolve_sway_locale` both write their nil check
as a `case`/`when` rather than an `if x.nil?`, because Steep narrows the result
to a definite non-nil type through the first form and not always through the
second.

A specific jurisdiction arrives on `LegislationPipelineRun`, and defaults fall
back to `DEFAULT_LOCALE_NAME` when absent.

## A skipped extraction does not establish a text prerequisite

A skipped extraction does not establish usable text for parsing. Diagnosing a production failure requires the stored per-bill error plus artifact evidence from that run.

execute_extract_text supplies usable text when pre-existing on the bill or on disk, writing the text artifact and succeeding without requiring a local PDF. It returns skipped_no_pdf only when neither PDF nor text exists, leaving ParseSectionsService to reject blank text with a diagnostic error.

The planned production diagnosis correlates the failed bill's stage results with its text sources. Synthetic coverage of text recovery establishes current behavior, but does not establish which prerequisite was absent in a historical run. Missing retained evidence leaves that cause unresolved.

## Locale-scoped execution

Pipeline runs preserve the selected SwayLocale from the admin request through every stage. Single-bill context belongs to the bill; All bills context belongs to the selected jurisdiction.

The run persists sway_locale_id, scoping disk hydration and bill lookup to run.effective_sway_locale. Single-bill parsing supports jurisdiction-specific citations against locale-scoped LawSection rows, including non-amending bills. Maryland and Congress upstream acquisition remains incomplete: declared sources currently reach refusal branches, while hearing discovery still requires Legistar metadata.

Planned upstream adapters separate bill discovery, known-bill text acquisition, law loading and hearing inputs for each jurisdiction. Law readiness and indexes belong to the requested locale; another locale's corpus cannot satisfy a prerequisite. Default-graph verification starts without cached bill text or law sections, exercises prerequisite downloads, and uses recorded authoritative responses with deterministic model output. A failed provider cannot stand in for verified absence.

Planned lifecycle corrections preserve the caller's locale during seeding, reject indeterminate legacy restarts before enqueueing, and merge database membership with disk hydration even when some metadata already exists. These boundaries prevent a missing locale or partial disk cache from silently changing an All bills run's scope.

## Official source-link verification across jurisdictions

An official source link must identify the same bill that Sway displays. Cross-locale verification ties each emitted URL and reader href to recorded authoritative evidence for that exact bill.

Baltimore City legislation resolves through Legistar InSite's Gateway redirect mechanism to public `LegislationDetail.aspx` URLs carrying both a database record ID and a GUID (`https://baltimore.legistar.com/LegislationDetail.aspx?ID=...&GUID=...`). Ingestion and backfill processes eliminate the generic search address (`https://baltimore.legistar.com/LegislationSearch.aspx`), leaving unresolvable matters as null.

State of Maryland bills link directly to the Maryland General Assembly legislation detail portal (`https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/{external_id}?ys={session}`), identifying the specific measure and legislative session rather than landing readers on the generic portal root (`https://mgaleg.maryland.gov/mgawebsite`).

United States Congress bills link directly to Congress.gov bill detail pages (`https://www.congress.gov/bill/{congress}-congress/{type}-bill/{number}`), retaining distinct federal legislative identity rather than generic portal roots (`https://congress.gov`).

The model validates non-nil link uniqueness; the database has no unique link index. Multiple null links are permitted. Legacy duplicate generic links remain invalid for model saves until the backfill replaces or clears them. Reader coverage limitations belong to [[unlinked-bill-presentation]].

Verification ties each emitted URL and reader href to authoritative evidence for that exact bill, including its jurisdiction and session. A same-host URL naming a different valid bill or session fails verification against recorded fixtures across Baltimore City, State of Maryland, and US Congress.

## Runs, resume and restart

A `LegislationPipelineRun` records what was asked for, and `PipelineRunStage`
rows record what happened. `LegislationPipelineRunService#call` creates the run and
enqueues the job; the run is the operator-visible object.

Two recovery paths exist and they differ. `resume` picks up a failed run from
the stage that failed, and is deliberately restricted to failed single-bill
runs — resuming a partially failed all-bills sweep would have ambiguous
semantics about which bills to retry. `restart` re-runs from the beginning.
Resume copies the parent's `download_missing_assets` flag rather than accepting
an override, so a resumed run fetches assets on the same terms as the run it
continues.

Constructor stages and bill are optional for recovery calls that inherit them
from the parent. A fresh call still rejects empty or unknown stages before
creating a row. All entrypoints share the stage validator. Missing-asset
downloads default to true on a fresh call; restart inherits the parent's flag
when its override is nil and honors an explicit false.

The default call queues RunLegislationPipelineJob. skip_enqueue leaves dispatch
to the caller: the controller queues after its concurrency check, while seeding
runs the job synchronously. Recovery creates a new row linked by the parent's
database id string. Resume and restart pass matching origin values to the row
and job so resume skips finished stages instead of purchasing their work again.

### Admin controls are exercised through the browser

The run-control system example proves that an operator can trigger Force fail and stale-run Sweep through the rendered admin controls.

It signs in through the test session helper and uses the browser confirmation dialog, complementing request and component coverage.

### The sweep assertion follows persisted run state

The sweep redirects to the new-bill pipeline tab, so disappearance of the initiating button cannot establish success. The example waits for both targeted rows to reach failed status in the database.

### Request admission blocks every active run

The request checks for any active run and creates the new row inside one immediate transaction.

[[app/controllers/bills_controller.rb#BillsController#enqueue_pipeline_run!]] uses `active_any`, so an in-flight single-bill run blocks an all-bills request and vice versa. `requires_new: true` opens SQLite's `BEGIN IMMEDIATE` transaction before the check; concurrent requests queue at the write lock, and the later check sees the row created by the earlier request. The queue's global concurrency limit remains the second line of protection.

### Requests selecting both fetch stages force asset downloads

Selecting both `fetch-bills` and `fetch-hearings` forces `download_missing_assets` to true, including for a hand-built request that sends false.

[[app/controllers/bills_controller.rb#BillsController#run_pipeline]] enforces this at request time so the stored run records the same download requirement the browser control presents.

### Restart inherits the parent asset-download choice

An omitted asset-download choice on restart comes from the parent; an explicit request value remains authoritative.

[[app/controllers/bills_controller.rb#BillsController#restart_pipeline_run]] preserves the distinction between an omitted `download_missing_assets` key and an explicit false value; [[app/services/legislation_pipeline_run_service.rb#LegislationPipelineRunService#restart]] applies the inherited value when the override is nil.

### Bill refresh uses every active status

The Bill Creator's bill prop reports a pipeline run throughout queued, running, and every per-stage state.

[[app/models/legislation_pipeline_run.rb|The run model's ACTIVE_STATUSES]] constant is shared by the active scopes used for run admission and bill refresh. Omitting a per-stage value would report the bill as idle during active work and allow duplicate actions while a run still holds the global queue slot.

### An enqueue failure keeps the run and marks it failed

If queue dispatch raises after the run row is created, the row remains and its failure transition is logged.

[[app/controllers/bills_controller.rb#BillsController#enqueue_pipeline_run!]] preserves the run record for the activity history, marks it failed, and records the transition rather than deleting evidence of the refused enqueue.

The restart path imposes no parent-status requirement; resume rejects an ineligible
parent before creating any row.

### Queue ownership outlives an operator stop

Stopping a run changes its application status; the executing worker keeps its Solid Queue slot until it exits. A queued successor cannot share that slot safely.

The pipeline uses Solid Queue's supported `on_conflict: :block` with a global
four-hour concurrency lease. The full key is
`RunLegislationPipelineJob/legislation_pipeline_global`. The controller rejects
an already active application run, while the queue serializes jobs that overlap
during shutdown or operator recovery. Solid Queue does not implement `:raise`;
unknown conflict values take its blocking path.

A redelivered job for a terminal run returns before preparing bills or calling
any stage. Running jobs reread the run at stage boundaries and between bills,
so an operator stop cannot be overwritten by a service finishing with an older
in-memory state. A run-level service already executing finishes its current
call before the boundary check observes the stop.

A worker restart uses Solid Queue's normal claim recovery. Requeued terminal
runs exit through the entry guard and release their slot to the existing
blocked successor. Releasing a semaphore while its worker can still execute
would permit concurrent writes, so queue ownership remains until shutdown or
normal completion establishes that the previous execution has stopped.

### Restart rejects indeterminate runs without a locale

Restarting an all-bills pipeline run requires a determinable locale on the parent run.

When restarting a run, `LegislationPipelineRunService#restart` resolves the effective `SwayLocale` from the parent run. For a single-bill run, this resolves the parent's locale or the bill's locale. For an all-bills run, if the parent lacks a locale (such as legacy runs created prior to locale persistence), the service raises `MissingLocaleError` before creating a child run or enqueueing a job. This prevents indeterminate runs from defaulting quietly to Baltimore.


Concurrency belongs to the controller's locked active-run check and the job's
single-run Solid Queue limit, rather than a separate service predicate about
the retired external pipeline service.

Runs can also be abandoned — a container restart mid-stage leaves a row claiming
to be running. `ReclaimAbandonedPipelineRunsJob` exists for that case.

No loop deletes old run rows. The Python sidecar carried a six-hour
`delete_older_than` sweep and the Rails pipeline holds no equivalent.
A run row is what the activity log and the run history cite, so
the rows are kept. `ReclaimAbandonedPipelineRunsJob` runs every fifteen minutes
and force-fails a stalled run, which clears the state that blocks the next run
without removing the record, and operators hard-delete orphans through the bulk
endpoint that `docs/reference/legislation-pipeline-run-orphan-detection.md`
documents.

### The summarize stage logs per-bill progress

The stage that calls a model logs each bill as it finishes, with the elapsed
time.

It is the slowest stage by a wide margin, and an operator seeding data
otherwise watches a run that prints nothing for minutes and cannot tell a slow
call from a stuck one. The elapsed time is what makes the difference visible
without opening the database.

### Seeding trims each locale back to a fixed number of bills

Development seeding runs the pipeline and then cuts each locale back to the most recent bills, because the pipeline creates more than the cap names.

Before the trim, the cap decided only whether to seed again and how long the
returned list was, so it was not a cap on what the database held. The value is
also passed through a reader that refuses nonsense: the trim deletes everything
past the first N rows, so a zero or an unparseable value would delete every
seeded bill.

### Seeding fails loudly when a pipeline run does not succeed

Synchronous seeding raises when a pipeline run finishes in a non-success status.

When the pipeline ends in a failure status, synchronous seed execution raises `SeedBill::ServiceUnreachableError` rather than logging and exiting zero, ensuring that an operator sees the failure. Terminal success statuses are `:completed`, `:succeeded`, and `:partial`. The success list is memoized lazily on first access rather than stored as a class-level constant, avoiding eager-load `NameError` failures when the file is required before Rails boots.


### A run naming one bill seeds only that bill

When a run carries a bill, the first stage seeds that bill alone rather than the whole matter set.

Seeding everything would be quietly expensive rather than wrong-looking: every
later stage then walks the bills the run did not ask about — 188 unrelated ones
in the case that produced the rule — so a Refresh click on one bill becomes a
full sweep.

### Hydrated runs include database-only bills in the selected locale

Downstream-only runs without discovery hydrate pipeline membership from both disk metadata and persisted database bills.

When a run skips the `fetch-bills` discovery stage, it hydrates its `PipelineRunBill` membership from available on-disk metadata and unions those records with all persisted `Bill` rows belonging to the run's effective locale. This guarantees that bills present only in the database are not omitted from downstream stages, while preventing duplicate entries across the union.


### A stage that produced nothing is not a success

A stage that finished without producing anything is recorded as a failure, because resume steps over a stage it believes succeeded.

The invariant has a sharp edge, and the edge was the second defect. Refusing on
the first bill it cannot repair costs one bill on a per-bill stage and the whole
run on a run-level one, so a bill upstream no longer lists must not discard the
repairs that did work. The ordering follows from the same argument: a lookup
that dies on the network ends the stage, so the targeted downloads run before
the repairs and a ready bill's file is already saved when that happens.

An external id identifies a bill only inside its locale, so a stage refuses to
act on one two locales share rather than letting `find_by` settle on whichever
row it finds — the row it picks decides which directory the files land in.

### Which attachment is the bill text

The primary attachment is chosen as the actual bill text rather than as whichever attachment changed most recently.

Supporting documents go on being revised for months after the bill text is
final, so recency picks the wrong file more often than not. The choice also has
to survive the source's own untidiness: file names carry stray characters after
the extension, and a gate reading the raw string counted a PDF with a trailing
space as no PDF at all, which made a matter with attachments look like one with
none.

### One walk decides the per-bill order

Every stage of every run walks its bills through `#each_pipeline_run_bill`, and the order it yields is the order the per-bill grid shows rather than insertion order.

A regression in it is therefore two failures at once: bills are processed in an
order that does not match what an operator is watching, and every batch writes a
log line saying so.

[[app/services/fetch_bills_service.rb#FetchBillsService#seed_ar_rows]] assigns [[app/models/pipeline_run_bill.rb]] sort order only when creating the row. Repeated discovery preserves its place in the grid; [[bill-session-archiving#Ingestion and pending work]] describes identities excluded from new pipeline work.

### A broadcast that fails must not fail the run

Each of the run's broadcasts rescues its own failure, because an exception from a send does not stop at the send.

It travels back to whoever saved the record, and the pipeline job turns that into
a failed run — so a momentary problem delivering a progress message would end
the work the message was describing. Two of the three senders had no rescue.

### Where a stage's completion time is written

`RunLegislationPipelineJob#record_stage_result` writes each stage's completion
time under `at`, never under `finished_at`.

Readers of that hash spell the same key, and the job's own spec pins the key
set, so a rename in the writer reddens there rather than silently handing every
reader a nil timestamp. The surrounding run row does carry a `finished_at`, and
the two are easy to confuse; they are not the same value, since one belongs to
a stage and the other to the whole run.

### Which run the Bill Creator surfaces

The run the page shows is the newest one, whatever it finished as, and both Bill Creator views carry the activity log.

Falling back only to the most recent failed or partial run leaves a run that has
since succeeded hidden behind an older failure, which tells an operator the
opposite of what happened. The activity log was supplied by the single-bill view
alone for the same class of reason: the all-bills view rendered the panel with
nothing in it, so the log looked empty rather than absent.

The Pipeline tab's recent-run rows carry `created_at` and `completed_at` as UTC, second-precision strings. `completed_at` is null until the run is terminal; it is the run's timestamp, distinct from each stage's `at` value written by [[app/jobs/run_legislation_pipeline_job.rb#RunLegislationPipelineJob#record_stage_result]].

#### The failed-run alert links to its own run

The Summary tab's failed-pipeline alert carries the id of the failure it describes so its Pipeline link cannot select a different run.

[[app/controllers/bills_controller.rb#BillsController#last_failed_pipeline_run_summary]] keeps the failed run's id with its message and timestamp. The Pipeline tab normally chooses by URL pin, current activity, or newest run, and its recent-run selector is capped; the alert therefore pins its own run in the URL.

### The admin surface is index-only

The admin surface reads through `GET /pipeline_runs` alone. It carries no
`:show` route: only `Index.tsx` exists under
`app/frontend/pages/admin/PipelineRuns/`, so a detail URL has no page.

The two destructive actions are declared as explicit member and collection
routes rather than through the REST `only:` list, so the absent `:show` leaves
both in place. `POST /pipeline_runs/:id/force_fail` moves one in-flight run to
failed. `DELETE /pipeline_runs/orphans` applies the per-row `orphan?` gate —
status queued or running, created more than four hours ago, and no unfinished
`RunLegislationPipelineJob` row — across the candidate set. A single-row twin
of that delete is absent, since no surface called it. The run id in
the index table is plain text rather than a link, because there is no detail
page to link to.

The index passes its newest fifty runs to [[app/controllers/pipeline_runs/run_summary_serializer.rb#RunSummarySerializer#call]]. That serializer preloads bills and per-run bill/stage rows and calculates the totals before rendering, so the page receives small display rows without loading those associations once per run.

#### Force-fail returns to the working surface

Force-failing a global run can return the operator to the Bill Creator Pipeline tab that initiated it; a run tied to one bill always returns to that bill's Pipeline tab.

`back_to=bill_creator` selects the new-bill address only when the run has no `bill_id`. The new-page URL uses the canonical `bill_creator_tab` query parameter, while the page keeps its established `tab_key` prop, as described by [[bill-creator-shell#Why tab URLs retain legacy compatibility]]. [[app/controllers/pipeline_runs_controller.rb#PipelineRunsController#force_fail]] chooses that return path before either error or success response.

#### Force-fail records its reason before transition

The administrative failure reason is stored before the state-machine event so the failed run retains why an operator stopped it.

[[app/controllers/pipeline_runs_controller.rb#PipelineRunsController#force_fail]] writes `error_message` before `force_fail!`, replacing any prior pipeline error text with the explicit operator action.

#### The orphan lookup wrapper remains test-visible

The controller's private Solid Queue lookup wrapper delegates to the model query and remains because the focused request spec directly exercises that boundary.

[[app/controllers/pipeline_runs_controller.rb#PipelineRunsController#solid_queue_job_exists_for?]] has no action caller; [[spec/requests/pipeline_runs_solid_queue_anchor_spec.rb]] pins the wrapper's name and its query behavior against Solid Queue rows. The underlying exact JSON-path lookup and fail-closed behavior belong to [[app/models/legislation_pipeline_run.rb#LegislationPipelineRun#solid_queue_job_exists_for?]].

### Stuck runs require evidence of abandonment

The Bill Creator's stuck-run count and cleanup action use the same abandonment rule as scheduled recovery: an unfinished run has had no update for four hours and has no unfinished pipeline job.

An active run alone is not evidence of a stalled worker. Runs awaiting a live
summary batch remain protected even after four hours, and a queue lookup error
preserves the run rather than treating missing evidence as permission to fail it.
The cleanup action checks each candidate again under its row lock before
marking it failed, so a count loaded earlier cannot clear a run that has since
made progress. Run records stay available for audit; permanent orphan deletion
retains its separate age, status and queue checks.

### Auto-include dependencies are resolved once before the stage loop

The dependency closure for auto-included stages is computed once before iterating through stages, rather than repeatedly inside the loop.

Operator-selected stages reside in `run.stages`, whereas prerequisite stages missing from that list are resolved via `Pipeline::StageDeps.transitive_closure`. Because the dependency graph and the requested stages remain invariant throughout a run, computing the difference upfront prevents repeating the graph traversal across hundreds of per-bill stage iterations. The resulting set isolates prerequisite stages that run in backfill mode from operator-selected stages that run in discovery mode.

### Discrete stage execution encapsulates dispatch and failure boundaries

Stage execution isolates lifecycle transitions, handler dispatch, and thread-local state for a single stage within the pipeline sequence.

`RunLegislationPipelineJob#execute_stage!` encapsulates the execution of one pipeline stage. The method verifies active run status, establishes auto-include logging context, triggers the starting state transition, dispatches to run-level or bill-level runners, and settles the stage completion or batch deferral. Separating single-stage execution from the iteration loop keeps stage failure boundaries clean and allows the job to break early on external batch submission.

### Per-stage invalid transitions fail the run immediately

Invalid state machine transitions during stage dispatch are trapped narrowly and re-raised as stage errors to terminate the run cleanly.

The rescue for `StateMachines::InvalidTransition` wraps only the stage-level event transitions. If an invalid transition occurs during stage initiation or completion, catching and re-raising as `StageError` routes execution into `handle_run_failure` to mark the run failed and record diagnostic logging. This prevents an invalid transition from silently succeeding or stranding the run in an indefinite active state with held concurrency locks.

### Auto-include execution context is scoped and cleared in ensure

Auto-include execution context is passed to the activity logger via `Pipeline::Current` and cleared in an `ensure` block to prevent thread leakage.

When a stage runs under auto-include backfill, `Pipeline::Current.current_auto_include_context` supplies diagnostic details including the stage key, missing artifact reason, and triggering bill identifiers. Operator-selected stages leave this context nil so activity log payloads remain unchanged. Clearing the context in an `ensure` block guarantees cleanup upon normal completion, early batch suspension, or unexpected exceptions, preventing thread-local state from polluting subsequent stages on shared worker threads.

## Artifacts are files, not rows

Stage output lands on disk under `LEGISLATION_ROOT` — the untracked repo-root
`legislation/` directory — and nothing in the database indexes it. The admin
resource-cache panel reads the pipeline's own state instead of a table.

The word choice is load-bearing here: an *artifact* is this on-disk pipeline
cache, an *attachment* is an Active Storage object, an *asset* is
admin-uploaded media in the GCS bucket, and a *mirror* is the copy-an-external-
asset mechanism. `docs/terminology.md` fixes all four, because they are
otherwise interchangeable English words describing four different storage
mechanisms.

### Every artifact write replaces the file in one step

A stage writes its output to a temporary file beside the destination and renames it into place, so no reader can observe a half-written artifact.

Overwriting in place was safe only while nothing else read the tree during a run.
Two things now do: the summary prompt reads a rendered diff from disk, and the
artifact backup walks the whole tree while runs may be going. A reader arriving
mid-write gets a file that is part old content and part new, and a backup stores
that mixture as though it were a real version of the file — which a comparison
based on size would never notice was wrong, so the bad copy would stand.

A rename within one directory stays on one filesystem, where it is atomic, so a
reader sees either the whole previous file or the whole new one. The temporary
file carries a leading dot and the writing process's id, and is removed when a
write fails.

## Typographic markup and declared target resolution

Legislative drafting conventions denote statutory amendments using inline typographic markings rather than explicit prose instructions alone. The pipeline extracts these operations and attributes them to the codified laws they modify:

- **Typographic markup extraction (`Legislation::MarkupOps`)**: Gated by `LEGEND_PATTERN` (which detects legislative drafting keys such as `CAPITALS INDICATE MATTER ADDED` and `[Brackets] indicate matter deleted`), `MarkupOps` parses inline edits without false positives on unamended text. It identifies `[bracketed]` text as `:strike` operations and `ALL-CAPS` runs of 4+ words/characters as `:insert` operations. To prevent false positives, bracketed ranges are masked prior to capital scanning, and statutory structural tokens (`SECTION`, `SUBSECTION`, `BE IT ORDAINED`, enacting clauses, and Roman numerals) are excluded.
- **Hyphenated and Unicode dash citation normalization**: Section citations often span article-section hyphenations (e.g. `§ 1-5`) and Unicode dash variants (`[-‐‑‒–—―−]`). `ParseSectionsService` normalizes Unicode dashes to ASCII hyphens, collapses spacing around hyphens in article names to `" - "`, and strips parenthetical subsection suffixes (e.g. `(j)` or `(c-1)`) while preserving the full text in the citation anchor. Negative lookahead guards (including decimal suffix lookahead `(?!\.[A-Za-z0-9])`) prevent the Baltimore short form (`§ ART-SEC`) from falsely claiming Maryland in-body `... of the ... Article` citations, including decimal section numbers such as `§ 21-801.1(b) of the Transportation Article`. `derive_short_key` applies a two-shape lookup falling back between `art_1__sec_5` and `art_1__sec_1_5` to match law sections indexed under differing schema conventions.
- **Declared amendment target parsing**: Legislative bills declare their statutory amendment targets in introductory enacting headers (`BY repealing and re-enacting, with amendments, ...`). `ParseSectionsService` scans the preamble for all `BY_HEADER_PATTERN` blocks, selecting the first block not marked `without amendments` (falling back to the first `BY` block when all are `without amendments`) at ordinal 0 with `authoritative: true`, and retaining all other `BY` blocks as non-authoritative references (`authoritative: false`). Deduplication against the declared target checks both section and article identity (directly, through the title-prefix canonical article map, or through Baltimore short-form numeric article prefixes) so cross-article citations sharing a section number are preserved. Typographic markup found in Section 1 is attributed to the authoritative declared target.
- **Diff rendering (`GenerateDiffsService`)**: Sections with markup operations receive status `"markup_modified"`, and `GenerateDiffsService::MarkdownRenderer` formats unified diff blocks (`-` for strikes, `+` for inserts, unmarked context). Any unattributed bill-level markup operations render under a top-level section diff without inflating operation counts.

## Why it runs inside Rails

The pipeline was a Python sidecar until it was moved into Rails. On a single
Raspberry Pi, a second runtime meant a second container, a second dependency
set and a second failure mode for an operator with no second machine to fall
back on.

Bringing it into Rails put stage state in the same database as the bills it
produces, which is what made per-stage progress visible in the admin UI at all.
The archived Python source was deleted in July 2026; `app/services/legislation/`,
`app/services/legistar/` and `app/services/testimony/` are the surviving
implementation. Operator procedures live in `docs/operations.md`.


## Law sections stay within their jurisdiction

LawSection.by_sway_locale limits section lookup to the bill's SwayLocale. Identical section keys in different jurisdictions must never resolve to each other's law text.

The parser loads each jurisdiction's section identifiers, keys, articles, sections, and titles once. Exact matches use an index, and fuzzy matching uses the same keys. This avoids a database query for each citation. The diff service also scopes its lookup by SwayLocale and returns no match for an unresolved reference or missing jurisdiction.

### Typed citation indexes

The parser rebuilds each plucked row as an explicit typed tuple because Steep cannot infer the column types from an untyped array.

Ordered reference annotations preserve the shape used to assign each operation to its nearest preceding citation. The final fuzzy-match branch checks the key type before its separate index lookup so Steep can narrow both values.

### Title-prefix article disambiguation

Title prefix patterns map spelled-out article names to canonical article codes when statutory corpora index sections under abbreviated stems.

In Maryland, statutory PDFs processed by GenericLawAdapter index sections under three-letter article codes (such as `gtp` or `gin`) while bill text cites full English article titles (such as `Tax - Property` or `Insurance`). ParseSectionsService builds a runtime title-prefix map from exact_index titles formatted as `Article - <Name> § <sec>`. This maps normalized article names to their canonical article code, enabling exact lookup and disambiguating identical section numbers appearing in different articles. When an amendment targets an unindexed new section in a recognized article, the unresolved section reference normalizes its key and article to the canonical code rather than falling back to an unindexed English name.

## Parsed references are replaced together

ParseSectionsService replaces a bill's references and operations in one transaction, so a rerun produces one current set of results.

Two bulk deletes remove operations before references. This avoids row-by-row callbacks and dependent deletion while SQLite holds its write lock. Parsing updates its timestamp and source metadata but does not write the retired parsed_sections payload.

The parser accepts text-pattern operations and typographic markup from extracted text. [[legislation-pipeline#Typographic markup and declared target resolution]] owns the markup rules and their attribution to declared targets.

### The first header mention selects the body of law

The parser classifies the first 4,096 characters by the earliest Charter or Code keyword in the text. It defaults to Code when neither appears.

Taking the first matching keyword in a list is incorrect because some phrases contain other keywords. Comparing all match positions makes classification independent of keyword-list order.

### Operation text columns

Inserted text belongs in replacement_text. Strike and text-pattern replace matches belong in anchor_text, with replacement_text left empty.

The text-pattern parser does not split a replacement into old and new halves. ApplyOperations reports that incomplete replacement instead of silently applying it as a strike. Markup operations follow the separate reconstruction path described in [[legislation-pipeline#Typographic markup and declared target resolution]].

## Diff artifacts describe changes to existing law

GenerateDiffsService compares existing law with the result of applying amendment operations. It does not compare successive versions of a bill.

Its JSON and Markdown artifacts retain the established output shape. Timestamps use microsecond precision and the +00:00 UTC suffix. Summary remains null because summarization belongs to a later stage. Markdown receives internal rendering fields before those fields are removed from the stored JSON.

### Non-amending bills conclude successfully

[[app/services/generate_diffs_service.rb#GenerateDiffsService#empty_sentinel_payload]] stores an empty, zero-count sentinel when no references or operations exist.

Such a bill is a valid completed stage, not a processing failure. [[eval-prompt-manifest-normalisation#Why the summary dump refuses rather than falling back]] describes how eval verifies extracted text from that sentinel.

Raising an error for resolutions or appointments would consume the consecutive-failure budget and stop unrelated bills. Persisting the sentinel makes artifact-presence checks report completion.

### Diff storage follows file creation

The service writes artifact files before mirroring their JSON into bill_llm_provisioning. Database state must not claim that files exist before their writes succeed.

A database failure leaves the files available for reconciliation on a later run. Updating only the diff columns preserves summaries already stored on the provisioning record.

### Amendment operations are grouped once

The diff service loads section-linked operations in one query and groups them by reference, avoiding a query for each section.

Explicit ordinal ordering preserves application order even if a caller later removes the model's default scope. Bill-level text-pattern operations count toward the total without creating a section block. Bill-level markup operations instead produce the unattributed amendment block documented in [[legislation-pipeline#Typographic markup and declared target resolution]].


## Upstream jurisdiction adapters

Upstream pipeline stages delegate external discovery, text acquisition, law corpus loading, and hearing inputs to jurisdiction adapters.

Config-driven generic adapters decouple external integrations from hardcoded jurisdiction logic. `GenericLegislationAdapter` drives bill discovery and bill text acquisition from declarative YAML rules, supporting pagination, URL substitution, session resolution from `LegislativeSession`, and JSONPath mapping; session resolution prioritizes explicit configuration (`session`), or active `LegislativeSession` model naming for the locale rather than hardcoded jurisdiction conventions or legacy start-date attributes. Legacy jurisdiction-specific symbols like `:maryland_general_assembly` and `:mga` are eradicated in favor of `:generic_html`. `GenericHearingsAdapter` extracts committee schedules from HTML or REST responses into standard artifacts. `GenericLawAdapter` parses XML and JSON statutory archives into partitioned `LawSection` records. `GenericRosterAdapter` fetches official member rosters and builds verifiable `OfficialEvidence` records with dynamic evidence attribution (`evidence_publisher`, `evidence_jurisdiction`, `evidence_source_url`) and cryptographic SHA-256 digests. `GenericVoteAdapter` normalizes roll call ballots across diverse API formats. `GenericLegislatorVoteUpdateService` persists normalized votes via date-resolved roster term matching, casting vote timestamps to local calendar days via `vote_rules.timezone`. While `vote_rules.enable_historical_fallback` configures the planned historical official fallback described in [[current-legislator-term#Planned automatic legislator updates]], no importer exists today, so unmatched voters stay unmatched and the service records them in [[legislator-vote-upserter-guard-rules#What each upsert outcome means for vote coverage|vote coverage]] for each run that has votes.

Generic adapters encapsulate vendor transport exceptions into `BillProcessingError` to isolate pipeline callers from vendor-specific error leaks. Client resolution requires explicit declarations in locale rules, and auxiliary metadata or attachment queries can recover with non-raising defaults. HTML discovery in [[app/services/legislation/adapters/generic_legislation_adapter.rb]] resolves a nonblank configured session first, then the locale's active database session's nonblank upstream name or name. It never reads a locale document to supply a session, and missing or blank sessions raise a processing error before upstream discovery. Unresolved configuration therefore cannot resemble successful empty discovery.

Generic vote persistence writes a vote only when [[app/services/concerns/legislator_vote_upserter.rb]] finds a term covering the bill's anchor date. The vote row stores no term; score recomputation finds the term from the bill's dates. Direct fixtures in [[spec/factories/legislator_votes.rb]] create no term: a supplied term only chooses the vote's legislator, so historical and current vote scenarios supply terms covering their vote dates. [[legislator-vote-fixture-tests#Legislator vote fixture tests]] establishes identity, defaults and override preservation; those checks do not prove that runtime term matching selects a historically supported term.

In `GenericHearingsAdapter`, Legistar committee and hearing discovery logic executes directly within the adapter rather than delegating back to legacy service-level discovery methods. Upstream transport exceptions (`Legistar::Client::Error`, `Faraday::Error`) are encapsulated into `BillProcessingError`, and `legistar_client` strictly requires explicit client configuration in locale `hearings_rules`, raising `ArgumentError` when omitted. Pipeline fetch services (`FetchBillsService` and `FetchHearingsService`) eradicate vendor-specific rescues, legacy client fallbacks, and dead discovery modes, failing fast when connection rules lack a valid retrieval strategy.

### Exception encapsulation and fallback eradication

Generic adapters insulate pipeline operations from upstream vendor failure modes by normalizing proprietary transport errors into `BillProcessingError` across discovery, attachment retrieval, and metadata fetching.

Legacy adapters allowed vendor-specific client exceptions (`Legistar::Client::Error`, `Legistar::Client::HttpError`, `Legistar::Client::ParseError`, and underlying `Faraday::Error`) to escape into higher pipeline stages. Primary discovery routines in `GenericLegislationAdapter` and `GenericHearingsAdapter` rescue these vendor errors and re-raise them as `BillProcessingError` with sanitized diagnostic messages, preserving run-level fault isolation. For auxiliary enrichment paths such as attachment downloads and status lookups, transport errors are caught to return non-fatal default collections rather than terminating entire pipeline batches.

Implicit client defaults such as a locale's city are removed. Adapters require explicit client configuration within [[config/sway_locales]]; missing client declarations fail visibly instead of selecting an ambiguous upstream. Downstream fetch services rely on that boundary. The session-resolution boundary is described in [[legislation-pipeline#The legislation pipeline#Upstream jurisdiction adapters]].

For `GenericHearingsAdapter`, discovering committee hearings for Legistar matters (`discover_legistar_hearings`) validates matter identifiers through positive bounds and 31-bit limits (`MATTER_ID_MAX`), translating non-numeric tokens, missing matter 404 responses, or network timeouts into `BillProcessingError` while safeguarding against stale matter IDs. Secondary discovery queries like `matter_attachments`, `matter_histories`, and `event_items` safely catch upstream transport errors and return empty arrays, preventing transient network glitches during peripheral data enrichment from aborting bill ingestion. This architecture ensures that all upstream interaction logic resides within the adapter layer while downstream fetch services remain purely generic orchestrators.

This contract extends to downstream fetch services (`FetchBillsService` and `FetchHearingsService`). By stripping out vendor error rescues (`rescue Legistar::Client::Error`) and dead legacy methods (such as `discover_legistar_hearings`), the fetch services become simple orchestration wrappers around adapters. When locale rules omit a valid connection strategy, services raise immediately rather than falling back to hardcoded client configurations or unconfigured Faraday stacks.

### Upstream error isolation and boundary defenses

Transport failures and malformed upstream payloads remain strictly confined within the adapter layer to prevent pipeline run collapse.

Primary discovery in `GenericLegislationAdapter` and `GenericHearingsAdapter` normalizes network failures, invalid JSON bodies, and HTTP status errors into `BillProcessingError`. This design isolates downstream services from vendor client implementations (`Legistar::Client::Error`, `Legistar::Client::HttpError`, `Legistar::Client::ParseError`, and `Faraday::Error`). When an upstream API suffers a service disruption or unreadable response during discovery, the pipeline records a clear, sanitized processing error rather than crashing the background runner with a low-level socket or parsing trace.

Boundary defenses distinguish primary identifiers from auxiliary subresources. In `GenericHearingsAdapter#discover_legistar_hearings`, missing matter identifiers trigger explicit validation (`verify_matter_exists!`) that raises `BillProcessingError` on 404 responses. This defense prevents the adapter from mistaking a nonexistent or stale matter ID for an authoritative empty hearing schedule. Conversely, auxiliary enrichment requests (`matter_attachments`, `matter_histories`, and `event_items`) safely catch upstream transport failures and return empty collections, preserving discovered core records even when peripheral metadata endpoints experience transient outages.

### Data-driven client resolution and cross-jurisdiction safety

Adapters strictly require explicit client declarations in locale rules, preventing accidental data pollution across civic jurisdictions.

Legacy implementations permitted adapters to fall back to `target_locale.city` or query external YAML schemas through `SwayLocale::DocumentReader` when client configuration was omitted. This implicit resolution created silent coupling risks, where a misconfigured locale could inadvertently query endpoints intended for another city or council. Under data-driven rules, `legistar_client` raises `ArgumentError` immediately whenever the `client` key is missing, nil, or blank.

Session resolution follows the configuration and active database boundary described in [[legislation-pipeline#The legislation pipeline#Upstream jurisdiction adapters]].




## Congress API paths and discovery failures

Congress API calls preserve the configured version path, and unsuccessful HTTP responses fail the fetch-bills stage before downstream work begins.

The configured base URL contains `/v3`. Relative `bill` paths preserve that
prefix for discovery, single-bill details, text versions and committees;
leading-slash paths instead reach the host root and return 404. Adapter tests
include the real versioned base path to exercise URL composition.

All-bills discovery selects the Congress ordinal from the requested locale’s
declared term calendar using `TermWindow.cycle_start_year`, including the
January convening boundary. Single-bill requests keep their explicit historical
Congress number. The shared service passes its existing discovery time budget
to adapters, bounding when another detail request may start.

Congress discovery raises on non-success HTTP responses and reports the status
without including response bodies or credentials.

## Congress introduced text versions

Congress discovery and missing-text fallback share the official introduced-version URL rule: House bills use `ih`, and Senate bills use `is`.

The mapping covers the published bill and resolution types, rejects unknown
types explicitly, and keeps discovery and text backfill from constructing
different PDF addresses. The source convention comes from the official
[GovInfo congressional bills documentation](https://www.govinfo.gov/help/bills).
An API-provided text-version PDF URL still takes precedence during backfill.

## Published bill text repairs missing PDFs

A valid edition code does not guarantee that a bill was published in that edition. Congress acquisition repairs failed guessed or cached PDF URLs using the bill’s published text versions.

The Congress download adapter first verifies the supplied download by status
and PDF magic bytes. If it fails, the adapter tries the official text endpoint’s
PDF candidates in order, followed by the introduced URL when distinct. An
available PDF replaces the cached URL atomically while preserving sponsor,
chamber and other metadata. Discovery and backfill share this path; an existing
metadata file cannot prevent a missing PDF from being repaired. Explicit
fetches continue to refresh files rather than trusting a local cache.

For example, a Senate resolution may have only an Agreed to Senate (`ats`)
PDF, while a House resolution may have only an Engrossed in House (`eh`) PDF.
No resolution-specific guessed mapping replaces the published versions list.
If no candidate provides PDF bytes, acquisition fails with a bill identifier
and status-only diagnostic. It cannot silently claim a successful download and
leave extraction without text. The parser continues to reject missing input.

Regression coverage verifies failed cached URLs, unavailable candidates,
metadata preservation and fresh discovery through extraction and parsing.
Other providers retain their own acquisition adapters; this repair adds no
jurisdiction branches to shared parsing or pipeline stage handling.

## Empty discovery is a stage failure

Every discovery provider must return at least one usable bill for the fetch-bills stage to succeed, including providers added for future locales.

`FetchBillsService` rejects an empty normalized discovery result before seeding
bills or persisting artifacts. The error identifies the selected locale, so a
run with no work fails at discovery before downloading a law corpus or reaching
extraction. The same rule applies when a provider returns no bills after an
empty upstream response, an unreadable first page, or an exhausted time budget.
An adapter may still return partial results when a later page fails; this
contract does not reject bills already discovered. Backfill and disk hydration
retain their separate empty-result behavior.

Tests exercise a synthetic provider symbol and locale through the shared
dispatcher, including a positive result, without depending on the built-in
jurisdiction branches.

## Law artifact readiness

Statutory law artifacts and database sections are partitioned by jurisdiction to isolate pipeline readiness checks.

`Pipeline::ArtifactPresence.present?("fetch-law")` verifies that both the jurisdiction's `section_index.json` file and its persisted `LawSection` database rows exist. Artifact paths are partitioned by the locale's path segment (`legislation/law/<locale-segment>/`). Legacy Baltimore root layout compatibility is preserved when the scoped folder is absent, while foreign-corpus fallback is strictly forbidden for other jurisdictions to prevent false readiness signals.

## Congress law corpus acquisition

A cold Congress law cache downloads the current nonreserved US Code title archives from the House Office of the Law Revision Counsel before ingestion. Existing local normalized XML and JSON remain usable offline.

The official download catalog supplies release-specific ZIP links on `uscode.house.gov`. Titles labeled `[Reserved]` are excluded because their catalog links can return an HTML page instead of an archive. Downloads accept only that HTTPS host and its releasepoint paths, reject redirects, and stream each archive to disk with compressed, expanded-title, and aggregate byte limits. ZIP entries have fixed title filenames rather than arbitrary extraction paths, and their expanded sizes and checksums must match the archive.

Acquisition stages every title in a temporary directory and publishes `raw` only after all downloads and parsing succeed. A file lock serializes competing bootstraps. Failed acquisition or parsing rolls back database writes and leaves no published raw corpus or successful section index; partial markdown files are never readiness evidence. A retry starts a fresh staging directory.

Official USLM is namespaced and contains title and section numbers in elements rather than the attributes in older local exports. The parser reads one section at a time, takes canonical identifiers from the statutory main title, and ignores quoted or note sections to prevent overwriting law with commentary. Historical appendix archives use a different structure and are excluded from automatic acquisition; the downloaded corpus covers numbered titles. Statutory text omits editorial notes and source credits, preserves paragraph boundaries, and retains upstream section status. Empty or malformed corpora fail visibly instead of producing a successful empty index.

Some US Code titles publish multiple enacted provisions with the same canonical section number. Their text remains together in one canonical `LawSection`, separated by headings and a markdown rule; a later provision never overwrites an earlier one. The index is active if any variant is active, and counts reflect unique citations. Merging considers only sections encountered in the current ingestion, so repeating a run does not append the variants again.

## Maryland PDF law corpus acquisition

Maryland's current statutory Code comes from the Maryland General Assembly article catalog and its per-article PDF links.

The configured corpus path is relative to the locale's law root and points to `raw`. Catalog results include constitutional material, so acquisition keeps only statutory article codes beginning with `g`. PDF URLs come from the article-link endpoint because their session paths change. A manifest records article codes, resolved URLs, filenames and SHA-256 digests; only a complete verified corpus is published. Failed refreshes preserve a complete prior corpus for offline parsing.

[[app/services/legislation/remote_pdf_law_corpus_service.rb]] returns an unchanged status without PDF downloads only when the resolved article URLs match and every expected PDF still has its recorded digest. Missing or changed files are reacquired; if refresh then fails, a complete verified prior corpus remains available as the cached-offline result.

### Filters and resolves official article URLs before caching PDFs

Catalog discovery keeps statutory article codes, follows each official dynamic article link, and publishes a manifest only after every downloaded PDF is verified.

### Skips PDF downloads for an unchanged verified corpus

A repeated catalog and resolved URL set with a complete digest-verified cache avoids article PDF downloads.

### Fetches and parses Maryland Code when the local corpus is absent

An absent Maryland PDF corpus is acquired from the configured catalog before law ingestion, allowing a pipeline run to produce sections instead of failing at the missing `raw` directory.

### Parses article PDFs into locale-scoped law sections

Maryland article PDFs become locale-scoped law sections and index entries.

[[app/services/legislation/adapters/generic_law_adapter.rb]] extracts each configured article PDF with [[app/services/mupdf_extractor.rb#MupdfExtractor]]. When `@parsing` is `:pdf_statute_sections`, [[app/services/legislation/adapters/generic_law_adapter.rb#GenericLawAdapter#load_raw_corpus]] delegates to `load_pdf_corpus` and resolves `@config[:local_path]` via `resolve_configured_local_dir` within `law_root`. Article codes remain identifiers, dash variants normalize to hyphens, structural dividers and page furniture are stripped, repealed or reserved single-status sections populate their body from their status heading, and malformed articles do not replace the previous section index or commit partial rows.

The parser distinguishes genuine section headers from wrapped in-body cross-references by detecting compact header styles (`^§[0-9]`). In real Maryland General Assembly PDFs, statutory section headers omit whitespace after the section symbol, whereas wrapped table cells and cross-references contain spaces or bare markers; inside an open section, wrapped references are preserved in the statutory body. Genuine headers with decimal title segments or omitted trailing periods normalize to canonical ASCII hyphen keys.

Because Maryland code PDFs omit section catchlines, the Page 1 article header provides the default title, and first body lines like subsection markers remain within the statutory body rather than being stolen as titles. Bare repealed section stubs lacking body lines default to standard placeholder status. When a PDF publishes both currently effective and future-contingent versions of the same section, duplicate keys merge into a single canonical section row and markdown artifact joined with horizontal dividers, preserving all effective banners and deduplicating identical titles.

### Readiness accepts the configured retrieval and parser

[[app/models/sway_locale/readiness_preflight.rb#SwayLocale#ReadinessPreflight]] checks law retrieval and parsing identifiers against their separate supported sets. Maryland's `configured_pdf_catalog` retrieval and `pdf_statute_sections` parser are recognized as automatic capabilities, matching [[app/services/legislation/adapters/generic_law_adapter.rb#GenericLawAdapter#load_corpus]].

### Rejects malformed later articles without replacing prior sections

Every article is parsed before rows or index files change, so an empty or malformed PDF preserves the previously published Maryland law sections.

### Extracts native text and strips repeated page furniture

The local Maryland fixture has native text on multiple pages. Repeated article headers and printed page numbers are excluded from stored section bodies.

## Why run_run_level_stage rewraps a stray BillProcessingError-shaped failure as StageError

Run-level stages fail the pipeline run on discovery errors while bypassing isolated per-row failures.

Run-wide discovery and adapter failures in run-level stages fail the run with `StageError`, whereas isolated per-row parse errors bypass failure with a logged warning; see [[run-legislation-pipeline-job-internals#Why run_run_level_stage rewraps a stray BillProcessingError-shaped failure as StageError]].

