---
mode: explanation
summary: "Why Bill Creator tabs each get a canonical /admin/bill_creator/:id/<tab> URL, and how legacy bookmarks and redirect_to call sites keep working."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why Bill Creator tabs each have a canonical URL

Bill Creator new + edit are reached via `/admin/bill_creator/*` so the admin
Drawer stays in admin mode while creating or editing bills. Each `ETab` has
its own canonical URL (`/admin/bill_creator/:id/<tab>`) via `defaults:
{tab_key: <name>}`, so `BillsController#edit` and the `BillCreator`
component keep reading `params[:tab_key]` unchanged. `ETab.PipelineLlm` was
renamed `"pipeline_llm"` -> `"pipeline"` in the same commit; the legacy
`/:id/edit` redirect translates the old value so bookmarks still resolve.

## Why `edit_bill_creator_path` stays a redirect

`edit_bill_creator_path` stays a 302 redirect to the canonical tab URL, so
any not-yet-migrated `redirect_to edit_bill_creator_path(...)` call site
keeps working. The translation table maps legacy `ETab` values (notably
`"pipeline_llm"` -> `"pipeline"`) onto the new segment; `tab_key` is dropped
from the query string so the path form stays the single source of truth.

Bare `/admin/bill_creator/:id` with no tab segment defaults to the Creator
tab, and forwards any query params so callers that build URLs like
`bill_creator_path(@bill, saved: "Foo")` still land cleanly.

## Why the legacy `/bills/*` redirects exist and are ordered first

Legacy `/bills/*` Bill Creator redirects MUST be declared BEFORE
`resources :bills` — otherwise `show` (`GET /bills/:id`) captures
`bills/new` as `:id => "new"` and 404s before the redirect fires. See
`spec/requests/legacy_bill_creator_redirects_spec.rb`.

They redirect with 302, not 301, so browsers don't cache the redirect
forever. The query string forwards onto the canonical URL, sharing the
legacy `?tab_key=` -> path-segment translation with `edit_bill_creator_path`.

## Why `BillCreatorTabRedirects` is a shared concern

`OrganizationsController` and `BillOfTheWeekScheduleController` both need to
send an admin back to the Bill Creator tab they submitted a form from, so the
tab-to-path map (`TAB_KEY_TO_PATH_HELPER`) and the redirect line live in one
concern instead of being duplicated in each controller. The older
`"pipeline_llm"` key is still listed in that map so a form cached in
someone's browser still lands somewhere sensible.

## Why the schedule spec pins every entry in TAB_KEY_TO_PATH_HELPER

After saving, `BillOfTheWeekScheduleController` decides where to send the
browser by looking the submitted `tab_key` up in `TAB_KEY_TO_PATH_HELPER`
and calling that helper by name. `spec/requests/bill_of_the_week_schedule_spec.rb`
pins EVERY entry in that table, the old `"pipeline_llm"` spelling and the
fallback for an unrecognised value included, because the call is made
dynamically — nothing else would catch a wrong entry.

## Why `tab_key` no longer needs a query param to be present

Each tab has its own URL, and `config/routes.rb` attaches a `tab_key` to
it with `defaults:`. So `GET /admin/bill_creator/:id/creator` always
renders with `tab_key` `"creator"` in the props. The prop used to be nil,
because the value only arrived as a `?tab_key=` query param.

## Why `#update`'s redirect needs no re-appended query params

The bill form lives on the Creator tab, so `BillsController#update`
redirects back to that tab's URL. The bill id travels inside the path;
nothing re-appends `?tab_key=` or `?bill_id=`. The `PreservesCreatorUrlParams`
concern that used to do that was deleted, because every redirect target
now carries the bill id in its path.

## Why a near-miss tab segment gets no explicit 404

The four tab routes spell their segment out in full, so a near-miss
segment like `not_a_tab` matches none of them and falls through to the
bottom of `config/routes.rb`. There is no explicit 404 handler for a
near-miss tab name specifically: adding one would mean a pattern
constraint on every route, or a second catch-all, and both cut against
the way the rest of the app is routed. What answers instead is whatever
the bottom of the routes file does with an unmatched path — see
[why the catch-all redirect is production-only](catch-all-enabled-production-only.md): only production draws a catch-all, so a near-miss tab name
answers 404 everywhere else. Either way, the near-miss segment never
renders a tab.

## Why the legacy redirects have their own request-spec contract, not just implicit coverage

No Ruby code reaches the legacy `/bills/new` and `/bills/:id/edit` routes
any more — every controller calls `new_bill_creator_path` or
`edit_bill_creator_path` directly — so
`spec/requests/legacy_bill_creator_redirects_spec.rb` IS the contract for
those redirect entries. Without it, a future cleanup could quietly delete
them and break every existing bookmark or emailed link that still points
at the old URLs.

Half that contract is "the redirect entries exist and work". The other
half is "the named helpers `new_bill_path` and `edit_bill_path` still
point at the old URLs". The type checker reads
`path_helpers.rbs` but cannot see what the helpers resolve to at runtime,
so dropping `as: :new_bill` from a route would break callers without a
peep — the type checker would only notice once the helper was removed
from `path_helpers.rbs` as well.

## Why `OrganizationsController#create` threads `tab_key` through its redirect

The Organizations panel appears on two tabs of the Bill Creator: the
Creator tab and the Summary tab. The form posts the tab it came from as
`tab_key`, and `OrganizationsController#create` uses that to send the
admin back to the same tab they submitted from, via
`BillCreatorTabRedirects`. The bill id travels inside that same redirect
path.

## Why `sway_locale_id` is required in system-spec navigation helpers

`AdminSystemHelpers#navigate_to_llm_accordion` and `#navigate_to_pipeline_llm_tab`
both visit their tab URL with `?sway_locale_id=#{bill.sway_locale_id}` in
the query string, and that parameter is not optional. The admin test
fixtures build an admin user with no address, so `User#sway_locales`
returns `[]` and `SwayLocale.default_locale` (congress) does not exist in
the test database. With no locale id in the URL,
`ApplicationController#find_current_sway_locale` runs out of options and
returns `nil`, which reaches the page as `sway_locale: null`.
`BillOfTheWeekCreator.tsx` then throws `TypeError: Cannot read properties
of null (reading 'id')` inside a `useMemo`, before its own
`if (!locale) return null` guard can run. Sentry's `ErrorBoundary` swaps
the whole admin tree for the "Sway had an issue loading the page"
fallback, so every `data-testid` the specs look for disappears. Passing
`sway_locale_id` lets `ApplicationController#set_sway_locale_id_in_session`
set the cookie before `find_current_sway_locale` runs, the locale resolves
to `bill.sway_locale`, and the admin tree mounts normally.

`#navigate_to_llm_accordion` visits the Summary tab specifically because
the current admin UI moved the LLM summary and pipeline controls out of
the in-page accordion and onto their own `BillCreatorShell` tabs, then
split that combined tab in two: "Pipeline & LLM" (run controls and cache
visibility) and "Summary" (LLM summary and organization positions). The
Summary tab is where `BillCreatorLlmSummary` and `BillCreatorOrganizations`
live and where the `data-testid` attributes the admin LLM, summary
editing, supplemental testimony, org positions and paste-summary specs
look for are rendered. The old helper name is kept so existing call sites
need no edits.

`#navigate_to_pipeline_llm_tab` visits the OTHER half of that split — the
pipeline run controls, `ResourceCachePanel`, `FetchedBillsPanel`, and
`ActivityLogPanel`, used by specs like the orphan bulk-delete and pipeline
run conflict banner tests. Its URL segment is `pipeline`, not
`pipeline_llm`, to match the value in the `ETab` enum.

## Why `BillCreatorPage.tsx` translates `tab_key` client-side

The `/new` route, which has no bill id, passes `params[:tab_key]` straight
through, so an old bookmark like `/admin/bill_creator/new?tab_key=pipeline_llm`
arrives at `BillCreatorPage.tsx` carrying the name that tab used to
have. `normalizeTabKey` translates that one renamed value, and turns
anything else it does not recognise into Creator, so `<Tabs>` always has a
tab that matches — an unknown name would draw the page with no tab selected.

The page component itself draws nothing when `user.is_admin` is false, which
is what the old UI did. The real admin check happens on the server:
`BillsController` turns non-admins away with `verify_is_sway_admin`.

## Why `LegacyBillCreatorTabs` lives in `app/lib`, not `config/routes.rb`

The legacy-`ETab`-to-URL-segment map (`app/lib/legacy_bill_creator_tabs.rb`)
used by the `edit_bill_creator` 302 redirect lives outside `config/routes.rb`
because Rails re-runs `routes.rb` top to bottom on every redraw, so a
constant assigned there would be reassigned each time and Ruby warns.
Development redraws whenever a route changes, and any spec calling
`reload_routes!` redraws twice more. Autoloaded from `app/` instead, a
redraw reads the constant rather than rebuilding it, and editing the map in
development still takes effect without a restart because the redirect
resolves the name per request.

## Why the frontend tab-key query-param interceptor was deleted

There used to be an `installCreatorTabInterceptor` call in
`entrypoints/application.tsx` that added a `?tab_key=<tab>` query param
onto every Inertia page visit. After tab state moved into the URL path
itself (`/admin/bill_creator/:id/<tab>`), Inertia visits can no longer drop
that state, so the interceptor was deleted, with follow-up work still open.

## `ETab.PipelineLlm`'s value and the `Summary` split

`ETab.PipelineLlm`'s value is `"pipeline"` so it matches the URL segment
(`/admin/bill_creator/:id/pipeline`). It used to be `"pipeline_llm"`, and
the old `/:id/edit?tab_key=` redirect in `config/routes.rb` still turns
that older string into this value, for outside bookmarks and any caller
still building URLs the old way.

`ETab.Summary` is the editing work that comes after the pipeline: the LLM
summary and the draft organization positions. It was split off from the
pipeline tab so that tab's live-refresh list no longer has to carry the
summary data, and so an operator can work on one job at a time.

## Why `app/frontend/components/bill/creator/constants/index.ts` stays at this path for now

The path was shared with the since-deleted V1 tree, which imported the
constants from here. The admin creator is now the only code using it, so
it can move into `components/admin/creator/`; that move has not been made
yet.

## The frontend `ROUTES` constant (`app/frontend/sway_constants/routes.ts`)

The Bill Creator lives under `/admin/bill_creator/*`, so the side drawer
stays in its admin form while an admin creates or edits a bill. The older
`/bills/new` and `/bills/:id/edit` paths still work: the server redirects
them to the matching `/admin/bill_creator/*` path, so old bookmarks and
email links keep working.

Each tab has a path of its own (`/admin/bill_creator/:id/<tab>`), so a
link to one tab can be shared, and the drawer can keep the open tab
highlighted by matching the start of the path. `billOfTheWeekCreatorTab`
is the front-end twin of the Ruby path helpers for those same tabs
(creator/schedule/pipeline/summary).

The `/admin` landing page that lists the admin tools, plus the pages
under it: `AuthLayout` switches the sidebar to its admin version whenever
the current URL starts with `/admin`.
