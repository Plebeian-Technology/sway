---
mode: explanation
summary: "Why BillsController's index/show/new/edit/create/update actions, its pipeline-trigger actions, and their shared private helpers are shaped the way they are"
status: agent-extracted
related: [docs/explanation/bill-score-builder-variants.md, docs/explanation/pipeline-run-request-transaction-lock.md, docs/explanation/bill-creator-artifact-panel-serializers.md]
---

# `BillsController` design

## `#index`

`BILLS_INDEX_PAGE_SIZE` bills the index pages with a growing window
(`?page=N` = first N * `BILLS_INDEX_PAGE_SIZE` bills), not separate slices,
so every partial reload replaces everything on screen with no Inertia merge
props needed.

`allowed_sort_columns` only accepts sort columns from a fixed list, so a
request cannot inject an arbitrary column name into the SQL `ORDER BY`.

`all_categories` is sent eagerly, outside `InertiaRails.defer`, so filter
chips have data at first paint. `bills_total` is the search-filtered total,
also sent eagerly, so the client can tell whether bills exist beyond the
current window — one indexed COUNT per request.
`bills_index_scope` is the shared search-filtered scope between that eager
COUNT and the deferred window query, so the two can never disagree about
which bills are "in" the list. Its search clause is a
parameterized query, so user input cannot inject SQL, and it also escapes
the LIKE wildcards (`%` and `_`) in user input, so a search term cannot
smuggle in wildcards and force expensive full scans.

The per-bill user-vote lookup (`user_votes_by_bill_id`) is built INSIDE the
`InertiaRails.defer` block, so a partial reload that omits `bills` (and the
initial page paint, which loads deferred props separately) runs no
`user_votes` SELECT. `:categories` is eager-loaded in the same query so
categories are not queried once per bill.

The window itself differs by client: web always gets a window (page
defaults to 1); mobile/JSON gets the full list unless it opts in with an
explicit page param — mobile's `BillsListScreen` reads the whole array
today. The order ties-breaks on `id`:
`introduced_date_time_utc` is not unique, and SQLite orders equal keys
unpredictably, so a stable total order is what keeps the window consistent
as it grows.

No `districts` prop rides this response on purpose — it used to ride the
same defer group as `bills`, paying for GeoJSON serialization nothing
consumed.

## `#show`

`email_preview` is built from `LegislatorEmailText` — the same object the
mailer renders — so the compose modal previews exactly what will be sent.
`user_legislator_emails` carries send status, polled by the Bill page so
pending → sending → sent updates with no manual refresh (see
[Why Bill.tsx and BillOfTheWeek.tsx poll the props they
do](bill-page-polling-props-rationale.md) for the frontend half of that
polling contract).

## Why the `organizations` prop is flat rows, not nested Organization objects

The `organizations` prop on `#show` holds this bill's ACTIVE organization
positions as flat rows (`OrganizationBillPosition#to_sway_json`, with the
org nested inside) — NOT a list of `Organization` objects carrying every
position each org has ever taken. Rows once lacked a top-level `support`
and `bill_id`, which left the mobile app's stance filter showing empty
organization sections on every bill.

## Why `BillEditLink`'s visibility is proven from the prop, not the markup

`BillEditLink` (the "Edit bill" control on `/bills/:id` and every row on
`/bills`) decides whether to render purely from `user.is_admin`
in these page props. SSR is off (`config/initializers/inertia.rb`), so the
server never renders the React tree — the browser does, from this JSON.
Proving the link is truly ABSENT for a non-admin, rather than present in
markup and merely hidden by CSS, comes down to proving the `is_admin` key
itself never reaches that response.

`BillEditLink` is the one place that decides whether an "Edit bill" control
renders at all. Every surface that uses it — the bill detail page and all
five bill-list themes — inherits whatever `BillEditLink.test.tsx` proves, so
its checks are the load-bearing ones: only a Sway admin (`isSwayAdmin`,
never the unrelated organizations `isAdmin` flag) sees it, it always points
at the canonical `/admin/bill_creator/:id/creator` address, and a list row's
accessible name names the bill so a screen reader can tell twenty-four of
them apart.

`BillEditLink.test.tsx`'s "does not treat an unrelated truthy admin-shaped
field as a sway admin" example guards a naming collision: the
organizations/* components spell this same idea `isAdmin`, for a
completely different permission (organization admin). A user who
administers an organization, but is not a Sway admin, must still see
nothing here.

### `list-layouts/__tests__/billEditLink.test.tsx`

The admin "Edit bill" control has no single seam on the bills list —
`DefaultBillListLayout` renders each row through `BillCard`, while the
other four themed layouts (Banner, Ballot, Chamber, Cornerstore) draw their
own row markup directly. This runs the same admin/non-admin/signed-out
checks against all five, the same way `billEntryTitle.test.tsx` already
does for the title-splitting rule, so a layout that forgets the link fails
here instead of shipping unnoticed.

The five layouts are enumerated by capability — every layout that draws a
bill row — not by which file happened to be open first. Found via
`ls app/frontend/components/bill/list-layouts/*.tsx`, then confirmed each
is reachable from `billListLayoutFor` (`index.ts`) and `Bills.tsx`.

## `#new` and `#edit`

`#new`'s `activity_log` mirrors `#edit`: `@bill` is nil here, so
`activity_log_entries_prop` returns the global (all-bills) feed rather than
a bill-scoped slice.

`#new`'s `fetched_bills` isn't set from `LegislationPipelineRunSourcing`
(that concern injects `legislation_pipeline_run` /
`stale_pipeline_run_count` via `inertia_share` on every response) — it's built here so it mirrors `#edit`'s wiring, letting
operators see what's on disk before picking a bill (see
[Bill Creator's two artifact panel
serializers](bill-creator-artifact-panel-serializers.md)). The URL-driven
pipeline controls state (`**pipeline_controls_state`) is spread in the same
shape as `#edit` so `#new` is also shareable via URL.

`#edit` renders via `render_inertia_or_json` so the mobile JSON path
receives `activity_log_entries` inline rather than a placeholder value.

`resource_cache_rows` (`ResourceCachePanel.tsx`'s data) is always computed
when `@bill` is present, not gated on `tab_key` — partial reloads from the
picker/cable broadcasts drop `tab_key` from the URL, which made the panel
render empty after bill switches. The local variable name
reflects the current source (`PipelineRunBill.stage_results` +
`BillLlmProvisioning` — the webhook-based `BillArtifactMirror` table it
used to read is deleted); the Inertia prop key (`bill_artifact_mirrors:`)
is kept for client compatibility.

`fetched_bills_rows` is the fleet-wide inventory of bills with files on
disk, the counterpart to the per-bill `resource_cache_rows` above. It's
sourced from the queried bill's locale, falling back to
`current_sway_locale` for the All-bills view.

## `#create`, `#update`, `#destroy`

`#create`'s rescue catches `StandardError`, not `Exception`, so
`SystemExit` / `Interrupt` / `NoMemoryError` still propagate during
deploys.

`#update`'s early `return redirect_to ... if @bill.blank?` is UNREACHABLE,
kept as defence: `#set_bill` resolves via `find`, which raises
`ActiveRecord::RecordNotFound` (a 404) rather than leaving `@bill` blank,
so this redirect can't actually fire.

`#update_success_notice` returns nil on the Summary tab path, where
`LlmSummaryEditableSummary` already raises its own client-side "Summary
saved." toast — without this, Save summary produced two green toasts, the
server's naming the wrong form. `redirect_to` sets no flash for a
nil value, which is what makes returning nil here work.
`saved_from_summary_tab?` and `update_return_path` both read the same
`params[:return_tab]` parameter, so they cannot drift apart. See [Why a
bill save carries its own return tab
](bill-save-return-tab-routing.md) for `update_return_path` itself.

`create_vote` updates the newest existing `Vote` row in place, rather than
`find_or_create_by!` keyed on the roll-call numbers (which stranded the old
row whenever an operator corrected a number), so a bill ends up with
exactly one Vote; stragglers are purged after save. A new `Vote` fires
`after_create :create_legislator_votes`; updating in place fires
`after_update` instead, so a corrected roll-call number needs an explicit
`LegislatorVoteFetchJob` re-fetch here (new rows stay covered by
`after_create`, so nothing enqueues twice).

`bill_params` deliberately does NOT permit `:category` (the legacy
single-subject field) — it's retired from the form, written only by the
ingestion pipeline now.

## The legacy `reject_org_position` removal

The legacy `POST /bills/:id/reject_org_position` endpoint was removed —
replaced by `PATCH /bill_draft_org_positions/:bill_id-:index`, which emits
the `org_position_decision` audit-log entry the legacy action lacked. A
non-UI caller of the old endpoint must move to the new one.

## Pipeline-trigger actions: `cancel_pipeline_run_bill`, `resume_pipeline_run`, `restart_pipeline_run`, `run_pipeline`, `sweep_stale_pipeline_runs`

`cancel_pipeline_run_bill` cancels a `LegislationPipelineRun`. The pipeline
runs entirely inside Rails, so flipping the state machine to `cancelled` is
the whole operation — `RunLegislationPipelineJob` checks for it between
stages. Its `back_path` sends the operator back to the tab they cancelled
from; a global (all-bills) run has no `bill_id`, mirroring
`run_pipeline`/`sweep_stale_pipeline_runs`.

`resume_pipeline_run` resumes a failed single-bill run from its last failed
stage. A server-side guard in `LegislationPipelineRunService#resume`
validates the parent run's state BEFORE creating the new row; the
controller rescues `ResumeNotAllowed` and surfaces it as a flash error —
because it's raised before a row is created, `enqueue_pipeline_run!`'s
rescue surfaces it with no orphan row left.

`restart_pipeline_run` restarts a run from stage 1, allowed regardless of
the parent run's state. The wire field is `download_missing_assets`; when
omitted, the service inherits `parent_run.download_missing_assets`. React's
`handleRestart` deliberately omits the key so this hits that nil-inherit
branch — "redo what the parent did," not "use whatever the checkbox shows
now." `dma_param` stays nil when the key is absent, keeping the "operator
didn't specify" branch wired to service-side inheritance; the boolean cast
treats `"0"`/`"1"`/`"true"`/`"false"`/nil alike.

`run_pipeline` is the global pipeline run triggered from the Bill Creator
page. The wire field is `download_missing_assets`; the backend
re-computes it server-side (forced true when both fetch stages are
checked) so a hand-crafted request can't bypass that rule. `stages` drops
anything smuggled in through a hand-crafted URL by filtering against
`PIPELINE_STAGE_KEYS`. `target_bill` (from `params[:bill_id]`, which the
React picker POSTs in the body) takes priority over `params[:id]` for any
URL-nested call sites; `Bill.first&.id` was rejected as a no-id fallback
since SQLite's ROWID order can land on an arbitrary years-old bill.

`sweep_stale_pipeline_runs` recognizes every non-terminal state
(`PHASE_52_NON_TERMINAL_STATES`), not just queued/running, so a run
abandoned mid-stage (worker killed, host asleep) is recoverable too. `force_fail` covers every non-terminal state → `:failed`;
`mark_failed!` is the fallback when `force_fail` isn't available on the
row. (Compare [LegislationPipelineRun orphan
detection](legislation-pipeline-run-orphan-detection.md), which is a
different, age-gated sweep of the same non-terminal territory.)

## Why the pipeline-run lifecycle routes needed their own admin-gate coverage

The three pipeline-run lifecycle routes (`cancel_pipeline_run_bill`,
`resume_pipeline_run`, `restart_pipeline_run`) reach `BillsController`
through their own `delete`/`post` route lines rather than
`resources :bills`, so none of them was named in any file that includes
the shared "requires sway admin" example. Cancel had a
hand-rolled check that signed in a non-admin and pinned a redirect to
root; that check worked, but it could only ever see the browser refusal —
the gate answers a bearer client with a JSON 403 instead, and nothing
exercised that branch on these three routes. Resume and restart had no
coverage at all.

The remaining admin-gated actions on this controller got the same
treatment: the gate is checked per action, so covering `create` proves
nothing about `destroy`. The list of actions needing coverage came from
`rails routes -c bills` checked against the `before_action` list, not from
reading the controller for likely gaps. A bill id that does
not exist is fine for these checks: the lookup runs after the gate.

## `enqueue_pipeline_run!` and `render_pipeline_duplicate_run`

See [The request-level active-run check and its transaction
lock](pipeline-run-request-transaction-lock.md) for why the concurrency
gate and the run create share one `requires_new` transaction.
`perform_later` fires AFTER commit, so an `ActiveJob::EnqueueError` here
moves the row to `:failed` via the state machine (not `.destroy`, which
would skip the audit-log transition) before rendering the 409.
`StageAllowlistError` and `ResumeNotAllowed` are raised by the service
BEFORE it creates a row, so they surface as an Inertia error with nothing
to roll back. Past the duplicate guard, `created_run` copies the block's
return value to a local so Steep (the Ruby type checker) can prove it is
not nil.

## `render_paste_summary_errors`

422 response for `paste_summary` validation failures, on both surfaces.
The web path deliberately avoids the global Inertia `errors` prop, which
is shared with every other form on the page and would surface the paste
summary schema's `"/"` JSONPointer key as a top-level field-less error.
Errors instead ride a dedicated `flash[:paste_summary_errors]` slot,
mirroring the success `flash[:paste_summary] = :persisted` — the same
pattern as `flash[:activity_log_error]`. Mobile gets the standard error
envelope instead: the per-field errors array rides under `details`.

## `bill_creator_props`

`b[:override_categories]` carries id+name+active objects for the bill's
current category set, including soft-deactivated ones (needed for the
delete affordance — a soft-deactivated category isn't in
`active_categories`). `active` lets the frontend compute its own "at most 3
active" cap client-side, matching the server-side cap enforced in
[`Bills::CategoriesController`](bills-categories-controller-manual-assignment.md).
It does NOT overwrite the public `categories` string array.

`active_categories` carries id+name objects for the override Select
control — distinct from the public `all_categories` names-only string
array on the `/bills` index, since the POST create route needs ids.
`max_active_categories_per_bill` is served from here, not re-hard-coded
client-side, so the two copies can't drift — every path is refused
server-side regardless.

## Testing the /bills filter against real server props (spec/system/bills_filter_spec.rb)

The category buttons on `/bills` are built from the server's
`all_categories` prop, sent snake_case on the wire. A frontend unit test
that hands the component its own props cannot catch an `all_categories` vs
`allCategories` mismatch; a browser spec that drives the real page,
reading real server props rather than faked ones, can. The spec confirms
picking one category leaves only the bills that carry it, picking a second
widens the list to bills carrying either one, and unpicking every category
brings the whole list back.

`/bills` is public — `BillsController#index` skips the login check for
`:index` — so the spec needs no sign-in helper. Its shape copies the
public organizations and admin categories system specs: a JavaScript-driven
system spec, the same Capybara host `around` block, and no admin user.

Its two category fixtures use Title-Case names on purpose: the buttons
print the server's string exactly as stored — nothing re-capitalizes it —
so the fixture's stored name is the label the spec has to match. If
clicking the category buttons turns flaky and repeated fixes do not stick,
the fallback is to assert the "Showing N bills" count or the number of
bill cards instead of the click interaction itself.

Its three bill fixtures give Bill A only "Health", Bill B only "Housing",
and Bill C both, with fixed title strings so the spec can check whether
each one is on the page. Each bill gets its own `scheduled_release_date_utc`
because the `bills` table forbids two bills in the same locale from
sharing that date, and the factory would otherwise give all three the same
default of one day ago.

## Testing search, sort, and load-more together (spec/system/bills_search_sort_spec.rb)

The three `/bills` list controls — the title search box that waits until
typing stops, the sort dropdown, and the button
that loads more results — had frontend unit tests only before
this spec. No browser test followed the whole chain: type, pause, URL
changes, page refetches just the data that changed. All three
controls are the same shared components on every list layout, so driving
the default layout covers their test ids for every theme.

`legislators` preloads `with_active_term`: without it, `l.serving?` /
`l.active_term` pays `LegislatorTerm.current`'s unscoped scan once PER
legislator (~540 avoidable scans on Congress) instead of once for the
batch.

### Why `Bills.tsx` declares its reload-prop lists at module level

`LOCALE_SWITCH_PROPS` is every prop that changes when the reader switches
locale. `bills` normally arrives in a second request, so naming it here is
what brings the new list back in the switch's own response, instead of
leaving the page sitting on its loading placeholder until that second
request lands. `all_categories` is the same for every locale today; it
comes along anyway, so making it locale-specific later cannot quietly leave
the category chips showing the old locale's list.

`BILLS_RELOAD_PROPS` is the props that every action changing how much of the
list is shown — load more, sort, search — refreshes together, so the visible
bills and the total can never disagree. It is declared at module level so
the hooks' callbacks are not rebuilt on every render.

`WINDOW_RESET_PARAMS` covers `page`: sorting or searching again starts the
list over from the first page — "page 3 of newest first" says nothing about
where the reader is in a different order or a different set of results.

Sorting comes from the URL (`?sort` and `?direction`, checked against the
columns the server agrees to sort by). Search comes from the URL too
(`?search=`, matched against the title on the server after cleaning), and
waits for a pause in typing. Each hook reads and writes its own part of the
URL and asks for the reload; the layouts only draw the value it hands back
and call `onChange`.

### Why `toggleCategory`'s request only asks for `all_categories`

The filtering itself happens in the browser, over the bills already loaded.
The `router.get` call in `toggleCategory` exists only to put the selection
into the URL, so it can be shared and so back and forward restore it. It
re-fetches nothing but the tiny `all_categories` prop — the bill list is
never asked for again. But the chip does not light up until Inertia finishes
the visit, so it shows an error toast if that round trip fails rather than
letting the click appear to do nothing.

### Why the search and sort labels in `parityCopy.ts` note the underlying split

Web and mobile both show these labels, but they work differently
underneath: web sends `?search`/`?sort`/`?direction` to the server
(`BillsController#index` accepts only an approved list of columns), while
mobile filters and sorts its offline copy of the list in memory. Each
`sortOptions` value is `"<column>:<direction>"` drawn from that same
approved list.

`sortOptions` is declared `as const` so callers can read the exact
`"<column>:<direction>"` type straight off these values (web
`BillsSortValue`, mobile `billsList`). The labels are short on purpose:
they have to fit a half-width dropdown on mobile web and a small native
button, and the "Sort" heading above them supplies the missing context.

`pipeline_controls_state` lives in URL query params, not client state, so
an operator can share links that fully describe the page.

## `pipeline_controls_state` and `pipeline_preview_for`

`pipeline_controls_state` memoizes per request so the `bill_creator_props`
render path (which calls it directly for the Inertia props AND indirectly
via `pipeline_preview_for`) runs the param parsing + allow-listing exactly
once.

In `compute_pipeline_controls_state`, `bill_id` is the picker selection —
the Bill's database id as a string, since it lives in the URL — returned to
the frontend as `bill_id`, defaulting to `""` so the picker re-renders
cleanly when nothing is selected. The path `:id` is
authoritative on the edit flow (`/admin/bill_creator/:id/<tab>`);
`?bill_id=` is only the source on the id-less all-bills flow — the path id
wins, falling back to the query. `dma` (download_missing_assets)
defaults to true to match the DB column default; the operator's checkbox
is authoritative on submission, subject to `run_pipeline` forcing it true
when both fetch stages are selected.

`pipeline_preview_for` passes `bills:` and `download_missing_assets:`
through to `PipelinePreviewService` so the warn-alert input
(`prereq_violations`) actually fires — the service used to run with
`bills: nil`, which short-circuited that computation to its
empty-presence-map early return.

## `picker_bills`

`picker_bills` is a thin adapter over `BillCreator::PickerBillsSerializer`
(see [`BillCreator::PickerBillsSerializer`](picker-bills-serializer-design.md)),
which branches its interesting-score math on the locale class (local vs.
full) — the adapter keeps the `current_sway_locale` resolution local to
the controller.

## `legislator_votes_refresh_toast_for`

See [Why AdminBillView is a row, not a cookie
](admin-bill-view-cookie-replacement.md) for why this reads a
database row instead of a cookie. The refresh payload is built BEFORE
persisting `last_seen_at`: the reverse order would advance `last_seen_at`
even if the source-`pick` query then raised, silently losing the
notification. It's rendered in the bill's own locale timezone, not
hardcoded Eastern, falling back to Eastern for locales with no `time_zone`
set. `view.last_seen_at` is bumped last, so a payload-build failure can't
advance the cursor past an unseen change.

The bump is skipped when there is no payload and the row already exists. Both admin Bill Creator tabs poll `#edit` every five seconds, and
the bump was unconditional, so an idle open tab drove an `AdminBillView` UPDATE
every five seconds for as long as it stayed open — against a single SQLite
writer serving the whole application. Skipping it in the steady state costs
nothing observable: when `payload` is nil there is no change newer than the
cursor, so moving the cursor forward cannot alter what a later request shows.
The write still happens on the two occasions that matter — when a toast was
just built, so the same change is not announced twice, and when the row is new
and has to exist at all.

## `supplemental_testimony_args`

Shared by `#generate_summary` and `#regenerate_summary` so the two can't
drift — see [Why supplemental_testimony has its own
endpoint ](supplemental-testimony-clear-endpoint-rationale.md)
and [The supplemental-testimony write rule](supplemental-testimony-write-rule.md)
for the history and the write rule itself. `permit` also closes a type
hole here specifically: an unpermitted `params[:supplemental_testimony]`
can arrive as an Array via `supplemental_testimony[]=x`, which isn't nil
and would take the write branch unguarded.

## `PIPELINE_STAGE_KEYS`

The authoritative allow-list of pipeline stage names accepted from URL
query params — Rails throws away any incoming stage key it does not name.
The frontend `STAGES` array (`pipeline-controls/stages.ts`, rendered as
checkboxes by `BillCreatorPipelineControls`) duplicates the same key list,
but only for labels/subtext — it is not the source of truth. The two lists
drifting apart means a stage added to one side has no matching checkbox or
no matching server allow-list entry; `spec/integration/pipeline_stage_keys_drift_spec.rb`
fails the build when that happens. Separately,
`spec/integration/stage_deps_sync_spec.rb` keeps the TypeScript `StageKey`
union and the RBS `stage_key` literal-union in step with
`Pipeline::StageKeys::KEY_TO_SYMBOL.keys` — a different pairing checked by
a different spec.

## How `pipeline_stage_keys_drift_spec.rb` checks parity

`controls_path`/`controls_source` are `let`s rather than inline reads so
both examples read the same cached bytes and the disk is only touched once.

`STAGES` used to sit in `BillCreatorPipelineControls.tsx` and now lives in
`pipeline-controls/stages.ts`, so `PipelineStageSelector` can import the
`StageKey` union type alongside the array; the spec reads `stages.ts`. It
pulls out just the `STAGES` `ReadonlyArray` literal — from the `const
STAGES: ReadonlyArray` line to the closing `];` sitting on its own line —
so the regex scan does not match lookalikes elsewhere in the file: a `key:
...` callback parameter, a render `key` prop, or a `[key: string]` index
signature.

Drift has to be caught in both directions. One example catches "the server
gains a stage and the frontend forgets it" — no checkbox appears for the
new stage. The other catches "the server drops a stage and the frontend
keeps it", which quietly loses the stage an operator picked from URL state:
`pipeline_controls_state` filters against `PIPELINE_STAGE_KEYS`, so the
checkbox renders, the click registers, and the stage never runs.

## Why the pipeline-run concurrency spec dropped its "second run blocked" example

`spec/controllers/bills_controller_pipeline_concurrency_spec.rb` checks two
things: the controller shares the pipeline-run prop through
`inertia_share`, and it does not rescue `PipelineRunInProgress`. An earlier
example checked that a second pipeline run could not be queued while one
was already going, leaning on a `LegislationPipelineRunService
.concurrency_blocked?` method that has since been deleted, so it was
removed. That rule is now covered end to end one layer up, in
`spec/requests/bill_pipeline_runs_spec.rb`, which checks both surfaces (a
flash error on the web branch, a 409 on the JSON branch) and runs through
the real inline `active_any.lock("").first` gate rather than the dead
method.

## What `bills_controller_pipeline_preview_spec.rb` covers

Checks how the `pipeline_preview` Inertia prop is wired to the Rails-native
`PipelinePreviewService`. `#new` and `#edit` render the Bill Creator page;
when the URL carries a `?stages=` param they call
`PipelinePreviewService.fetch` and hand the result back as the
`pipeline_preview` prop. On a first load with no stages the prop is nil,
which is what the UI design asks for.

The admin-gate check for `#edit` sits next to these examples deliberately —
`BillsController` is already on the admin allowlist (see the admin
endpoints section of CLAUDE.md) — keeping the gate from being dropped by
accident as this file evolves.

## Why mobile's `deriveVisibleBills` mirrors the server's sort semantics exactly

`mobile/src/utils/billsList.ts`'s `deriveVisibleBills` filters and sorts
bills on the device the same way the server does: keep a bill if it
matches ANY of the chosen categories, then match the search text against
the title (trimmed, ignoring upper/lower case), then sort by
`"<column>:<direction>"`. Ties break on id, highest first, mirroring the
server's `:id => :desc`. A bill with no value for the sort column counts
as the smallest, matching the order SQLite gives empty values.
`mobile/__tests__/utils/billsList.test.ts` shuffles its fixture ids in a
different order than their dates on purpose, so a missing sort shows up.

### Why mobile filters and sorts in memory instead of asking the server

Mobile filters and sorts IN MEMORY over the full list already cached: the
offline SQLite cache is treated as the source of truth (loaded once, then
kept fresh in the background), so sending a search/sort request to the
server on every keystroke would break offline browsing for no real
benefit. The web instead sends the equivalent `?search`/`?sort` parameters
to the server — a deliberate mobile/web difference `[platform]`.
