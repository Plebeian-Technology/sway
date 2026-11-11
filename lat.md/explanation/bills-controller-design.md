---
lat:
  mode: explanation
---

# BillsController design

`BillsController` orchestrates bill browsing, detail presentation, and administration across web and mobile surfaces.

The controller provides bill collections, detail views, and pipeline management while coordinating search parameters and sorting specifications between server database queries and client presentation.

## Why the search and sort labels in parityCopy.ts note the underlying split

Web and mobile interfaces display identical search and sort labels while executing filtering and sorting through different architectural mechanisms.

The web client transmits query parameters to [[app/controllers/bills_controller.rb#BillsController#index]], which validates against an approved column allowlist and executes sorting within SQLite. In contrast, mobile readers filter and sort an offline list in memory. [[app/frontend/sway_constants/parityCopy.ts#PARITY_COPY]] defines `sortOptions` as an `as const` tuple so callers extract exact `"<column>:<direction>"` unions matching server sort orders.

## The web bills index grows a stable page window

The web index treats `page=N` as the first N pages of bills, so each load-more response replaces the visible list without Inertia merge props. Mobile receives the full list unless it requests a page because its current screen reads the full array.

The filtered total arrives eagerly while bills are deferred; both reads use the same search scope, so the count and rows agree. Sorting also breaks ties with bill id because equal introduction times otherwise make adjacent windows unstable.

### The count and list share one scoped query

[[app/controllers/bills_controller.rb#BillsController#bills_index_scope]] supplies the public index's locale, list mode, legislative session, and search criteria to both the eager count and deferred bill list.

On `/past_bills_of_the_month` ([[app/controllers/bills_controller.rb#BillsController#past_of_the_month]]), it scopes to [[app/models/bill.rb#Bill#past_of_the_month]]; on `/bills`, it scopes to [[app/models/bill.rb#Bill#for_legislative_session]] when a session is selected or `Bill.current_session` by default. A separate scope for either read could show a count that disagrees with the rows.

### Search treats wildcard characters as text

The title search escapes `%` and `_` before using a `LIKE` predicate, so user-entered punctuation remains literal search text rather than widening the query to unrelated bills.

The escaped search remains parameterized. [[app/controllers/bills_controller.rb#BillsController#bills_index_scope]] is the one scope used by both the count and list.

### Past Bills of the Month vs All Bills and historical sessions

The `Pages::BILLS` page serves two reader list modes — `"all_bills"` on `/bills` and `"past_bills_of_the_month"` on `/past_bills_of_the_month` — sharing one layout and filter pipeline while keeping their datasets distinct.

In `"past_bills_of_the_month"` mode, [[app/models/bill.rb#Bill#past_of_the_month]] selects only bills with a past or current `scheduled_release_date_utc` for the locale while excluding the currently featured [[app/models/bill.rb#Bill#of_the_month]]. Because featured selections span sessions and are protected from archiving, the legislative session selector is omitted in this mode.

In `"all_bills"` mode, the controller serializes the locale's sessions via [[app/serializers/legislative_session_resource.rb#LegislativeSessionResource]] and defaults `selected_legislative_session_id` to the active session. When a reader selects an inactive historical session via `bills_legislative_session_id`, [[app/models/bill.rb#Bill#for_legislative_session]] unscopes `archived_at` so archived historical bills can be browsed and opened read-only via [[app/controllers/bills_controller.rb#BillsController#show]].

## The bill page returns active organization positions as flat rows

The `organizations` prop holds flat rows for this bill's active organization positions, with organization fields nested under each row.

Top-level `bill_id` and `support` keep a row tied to the correct bill and expose its stance to clients such as mobile's organization filter.

Returning organizations with their full position histories would mix unrelated bills into the current bill's response. The request spec pins the row shape and its bill scope so consumers can rely on the top-level stance fields.

The frontend's [[app/frontend/components/bill/sway_utils/billPositions.ts#selectBillPositions]] repeats the bill check defensively, drops rows without summaries because they have nothing to display, and splits the remaining rows by support. Neutral positions remain in the complete list. [[app/serializers/bill_page_resource.rb#BillPageResource]] memoizes the serialized position rows in `organization_positions_cache` per bill so the `organizations` and `organization_bill_positions` props share one query and serialization pass.

## The index embeds user votes through a whitelist resource

The bills index serializes a reader's vote through [[app/serializers/user_vote_resource.rb#UserVoteResource]] rather than exposing the model's complete row.

The resource fixes the public vote fields, so internal columns such as `user_id` and record timestamps cannot become response fields when the table changes. The exact key set is pinned in `spec/requests/serializer_whitelists_spec.rb`.

## The Bill Creator separates category choices from override records

The category controls need active choices for adding a category and the bill's existing records for removing or restoring one.

[[app/controllers/bills_controller.rb#BillsController#bill_creator_props]] serves `active_categories` as id/name options and the per-bill `override_categories` with id, name, and active state. The latter retains a deactivated category so its existing association can still be shown and removed; its `active` value also lets the form enforce the active-category limit without changing the public category-name list.

## Bill creation rescues ordinary application failures

Bill creation catches `StandardError` so an ordinary failure can be reported while process-level exceptions still escape.

[[app/controllers/bills_controller.rb#BillsController#create]] owns this request boundary. Rescuing `Exception` would also swallow `SystemExit`, `Interrupt`, and `NoMemoryError` instead of allowing the process to stop or restart.

## The new and edit forms have separate bill prop shapes

The new and edit actions provide different bill payloads because the new form reads an unsaved record and edit decorates a persisted record.

[[app/controllers/bills_controller.rb#BillsController#new]] supplies `Bill.new.attributes`, which [[app/frontend/components/admin/creator/hooks/useNewBillInitialValues.ts#useNewBillInitialValues]] reads for form initialization. [[app/controllers/bills_controller.rb#BillsController#bill_creator_props]] decorates persisted `@bill.to_sway_json` with organization, provisioning, pipeline, and category data. All sixteen new-action props are callable, so a poll that names only a subset does not pay to build the rest of the form payload.

Calling the edit builder with an unsaved bill also resolves [[app/controllers/bills_controller.rb#BillsController#legislator_votes_refresh_toast_for]], which writes an [[app/models/admin_bill_view.rb#AdminBillView]] row using the bill id. [[db/schema.rb]] declares `admin_bill_views.bill_id` non-null, so that call cannot load a new form without violating the database constraint.

## The email-your-legislators modal has browser coverage

The system examples drive the four-step compose, verification, send, and status flow; the send button appears only after the user has voted on a bill.

The voter fixture sets registration and email-verification state after creation because the model's create callback resets those flags. The preview assertion re-queries through Capybara so a React rerender cannot leave a stale element handle.

## Why BillEditLink's visibility is proven from the prop, not the markup

`BillEditLink` decides whether to render purely from the `user.is_admin` prop, making property absence the definitive proof that non-admin responses exclude the control.

Server-side rendering is disabled, so the client constructs markup entirely from JSON props. Proving the control is absent for non-administrators requires confirming the `is_admin` key is omitted from the server payload rather than merely hidden via CSS.

Every surface using `BillEditLink` — including the bill detail page, the Bill of the Month page, and themed list layouts — relies on tests in `BillEditLink.test.tsx`. These tests verify that only Sway administrators (`isSwayAdmin`) receive the link, the link points to `/admin/bill_creator/:id/creator`, and screen readers receive distinct accessible names for each row.

Tests specifically guard against naming collisions with organizational administrative flags (`isAdmin`), ensuring organization managers without Sway administrative privileges cannot see the link.

### list-layouts billEditLink test notes

List layouts render bill rows through distinct components, requiring unified verification across all themes.

`DefaultBillListLayout` renders rows using `BillCard`, whereas themed layouts (Banner, Ballot, Chamber, Cornerstore) construct row markup directly. Test suites run administrator and signed-out scenarios across all five themes to ensure consistent link presence.

## New and edit actions in Bill Creator

The `#new` and `#edit` actions provide administrative state, activity logs, and pipeline controls across single-bill and all-bills flows.

`#new` provides a global activity log slice because `@bill` is absent, whereas `#edit` scopes entries to the active record.

`#new` constructs `fetched_bills` directly to mirror `#edit` wiring, enabling operators to inspect existing disk artifacts prior to bill selection. URL-driven pipeline controls (`**pipeline_controls_state`) spread identical properties across both actions.

`#edit` renders via `render_inertia_or_json` so mobile JSON requests receive `activity_log_entries` inline.

`resource_cache_rows` (`ResourceCachePanel.tsx`) computes whenever `@bill` is present without tab gating, preventing empty panel states during URL transitions that omit `tab_key`. The property key `bill_artifact_mirrors:` is retained for client compatibility.

`fetched_bills_rows` captures disk artifacts across the fleet, scoped to the current bill's locale or falling back to `current_sway_locale` for all-bills views.

## The create, update, and destroy actions

Write actions in `BillsController` manage transactional updates, error isolation, vote synchronization, and redirect routing.

`#update` includes an unreachable defensive guard for missing bills because `#set_bill` raises `ActiveRecord::RecordNotFound` on missing records.

`#update_success_notice` returns nil when saving from the Summary tab where client-side toast notifications already announce saves, preventing duplicate notifications. `saved_from_summary_tab?` and `update_return_path` read `params[:return_tab]` to synchronize redirect behavior. [[docs/explanation/bill-save-return-tab-routing.md|Why a bill save carries its own return tab]] documents return tab routing mechanics.

`create_vote` updates existing `Vote` records in place rather than creating duplicate rows during roll-call corrections. Updating in place triggers `after_update` rather than `after_create`, necessitating an explicit `LegislatorVoteFetchJob` dispatch for corrected roll-call numbers.

`bill_params` excludes the legacy single-subject `:category` parameter, restricting category assignment to the ingestion pipeline.

## The legacy reject_org_position removal

The legacy `POST /bills/:id/reject_org_position` endpoint was replaced by `PATCH /bill_draft_org_positions/:bill_id-:index` to generate required audit trail events.

The replacement endpoint emits `org_position_decision` audit-log events missing from the legacy implementation.

## Pipeline-trigger actions and life cycle management

Pipeline triggering endpoints manage execution state transitions and parameter inheritance across single-bill and fleet-wide runs.

`cancel_pipeline_run_bill` transitions `LegislationPipelineRun` records to `cancelled`. `RunLegislationPipelineJob` polls for this status between stages.

`resume_pipeline_run` restarts failed single-bill runs from their last failed stage. Pre-creation validation in `LegislationPipelineRunService#resume` prevents orphan rows if resumption is prohibited.

`restart_pipeline_run` restarts executions from stage 1. Omitting `download_missing_assets` allows the service to inherit the parent run's configuration rather than applying active UI toggle values.

`run_pipeline` triggers fleet-wide runs from Bill Creator, enforcing server-side asset download rules when both fetch stages are selected and filtering requested stages against `PIPELINE_STAGE_KEYS`.

`sweep_stale_pipeline_runs` transitions non-terminal runs to failed status, ensuring runs interrupted mid-stage remain recoverable. [[lat.md/reference/legislation-pipeline-run-orphan-detection.md|LegislationPipelineRun orphan detection]] covers companion age-gated sweep mechanics.

## Why pipeline-run lifecycle routes require dedicated admin authorization specs

Lifecycle routes reach `BillsController` through custom route definitions rather than standard resource routing, requiring explicit admin gate coverage.

`cancel_pipeline_run_bill`, `resume_pipeline_run`, and `restart_pipeline_run` are declared outside standard `resources :bills` routes. Shared administrative verification specs confirm both browser redirects and JSON 403 responses across all custom endpoints.

## enqueue_pipeline_run! and render_pipeline_duplicate_run

`enqueue_pipeline_run!` and `render_pipeline_duplicate_run` encapsulate concurrency locking and error translation during run initialization.

[[docs/explanation/pipeline-run-request-transaction-lock.md|The request-level active-run check and its transaction lock]] details shared transaction locks between concurrency gates and record creation. ActiveJob enqueue errors transition rows to failed status to preserve audit history before returning 409 responses. Pre-creation validation errors surface directly as Inertia errors.

## render_paste_summary_errors

`render_paste_summary_errors` handles 422 validation responses for pasted summaries across web and mobile surfaces.

Web responses route validation failures through `flash[:paste_summary_errors]` rather than the shared Inertia `errors` prop to prevent top-level pointer pollution. Mobile responses receive structured error details under `details`.

## Testing the bills filter against real server props

Browser specifications in `spec/system/bills_filter_spec.rb` validate category filter buttons against real server properties.

System tests verify snake_case property transmission and confirm multi-category filtering interactions without mocked responses. Fixtures utilize title-case labels and explicit release dates to ensure predictable DOM assertions.

## Testing search, sort, and load-more interactions

System tests in `spec/system/bills_search_sort_spec.rb` drive search debouncing, sorting, and pagination across real browser interactions.

Specifications exercise the entire interaction loop across query changes, network updates, and partial prop reloads. Legislator preloading scopes minimize query overhead during list generation.

### Why Bills.tsx declares reload-prop lists at module level

`LOCALE_SWITCH_PROPS`, `BILLS_RELOAD_PROPS`, and `WINDOW_RESET_PARAMS` are defined at module level to avoid reallocating prop arrays during renders.

Module-level definitions maintain referential stability for hook callbacks. Prop lists ensure that changing locales, search queries, or sort orders refreshes matching data sets atomically.

### Why toggleCategory request only asks for all_categories

Category filtering executes client-side over previously loaded bills, requiring network round trips only to sync URL parameters.

`toggleCategory` requests only the lightweight `all_categories` prop to update the address bar without re-fetching bill records. Round-trip completion triggers visual chip selection.

## pipeline_controls_state and pipeline_preview_for

`pipeline_controls_state` memoizes parameter parsing per request to eliminate duplicate calculation across Inertia props and preview calculations.

`compute_pipeline_controls_state` resolves bill identifiers with path parameters taking precedence over query parameters. `pipeline_preview_for` passes selected bills and asset settings to `PipelinePreviewService` to trigger prerequisite violation warnings.

## picker_bills

`picker_bills` adapts `BillCreator::PickerBillsSerializer` to provide locale-aware bill selection data.

[[docs/explanation/picker-bills-serializer-design.md|BillCreator::PickerBillsSerializer]] documents score calculation across locale tiers, while the controller manages locale resolution.

## legislator_votes_refresh_toast_for

`legislator_votes_refresh_toast_for` manages notification payloads for updated legislator votes using persisted viewing timestamps.

[[docs/explanation/admin-bill-view-cookie-replacement.md|Why AdminBillView is a row, not a cookie]] documents timestamp persistence. Updating viewing records occurs only when notifications exist or new rows are created, preventing redundant database writes during administrative polling intervals.

## supplemental_testimony_args

`supplemental_testimony_args` standardizes parameter filtering between summary generation and regeneration endpoints.

[[docs/explanation/supplemental-testimony-clear-endpoint-rationale.md|Why supplemental_testimony has its own endpoint]] and [[docs/explanation/supplemental-testimony-write-rule.md|The supplemental-testimony write rule]] document parameter handling rules and clear endpoint mechanics.

## PIPELINE_STAGE_KEYS

`PIPELINE_STAGE_KEYS` defines the authoritative server-side allowlist for pipeline stages received from query parameters.

Rails discards incoming stage names absent from this list, while `DEFAULT_PIPELINE_STAGE_KEYS` excludes `summarize-bill` so default pipeline runs do not summarize hundreds of bills. `spec/integration/pipeline_stage_keys_drift_spec.rb` enforces synchronization between server allowlists and frontend checkbox arrays.

## How pipeline_stage_keys_drift_spec.rb checks parity

`pipeline_stage_keys_drift_spec.rb` validates bidirectional synchronization between server and client pipeline stage definitions.

The specification parses `STAGES` from `pipeline-controls/stages.ts` and compares items against `PIPELINE_STAGE_KEYS`, detecting both unregistered server additions and unhandled client selections.

## Why the pipeline-run concurrency spec dropped its second run blocked example

Concurrency specifications retired outdated method checks in favor of end-to-end request tests.

`spec/requests/bill_pipeline_runs_spec.rb` verifies run locking across web and JSON endpoints against live database locks rather than deprecated unit methods.

## What bills_controller_pipeline_preview_spec.rb covers

`bills_controller_pipeline_preview_spec.rb` tests integration between the `pipeline_preview` prop and `PipelinePreviewService`.

Specifications confirm that stage parameters trigger preview calculations while first visits without parameters return nil. Administrative authorization checks sit alongside preview tests to safeguard route protection.

## Why mobile deriveVisibleBills mirrors server sort semantics exactly

`deriveVisibleBills` in `mobile/src/utils/billsList.ts` replicates server filtering and sorting logic for offline datasets.

Mobile applies category filtering, case-insensitive title search, and multi-column sorting with id-based tie breaking to match SQLite ordering: titles compare linguistically with `localeCompare`, while ISO-8601 dates compare lexically. Client-side filtering over cached SQLite databases maintains offline responsiveness without dispatching network requests for each filter interaction (a deliberate mobile/web difference `[platform]`).

## Why approve_org_position names :approved explicitly and refuses unhandled outcomes

[[app/controllers/bills_controller.rb#BillsController#approve_org_position]] matches the approved outcome Symbol explicitly so any new refusal outcome from [[app/services/approve_org_position_service.rb#ApproveOrgPositionService]] falls into the fallback branch instead of silently flashing approval.

When a second browser tab approves a position after another tab changes the underlying testimony state, the service returns a refusal outcome for private individuals, unacknowledged coverage, or missing claimed affiliations, and the controller renders an explicit error response while logging any unrecognized outcome Symbol.
