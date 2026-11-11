---
lat:
  mode: explanation
---
# The Bill Creator shell

The shell holds the bill picker, the tab strip and the run-conflict banner around whichever Bill Creator tab is open. Its job is to change which bill is being worked on without changing which tab the operator is working in.

## Why the tab survives picking a different bill

Existing-bill paths carry the tab in a segment; the new-bill path uses the
canonical `bill_creator_tab` query value, with `tab_key` as a legacy fallback.

Without it, picking the new-bill sentinel from any other tab visited an address
naming no tab, the server rendered the first one, and the operator lost the
screen they were working on. The sentinel is also labelled per tab: on the
pipeline tab "All Bills" means run every bill, not leave this tab, so treating
it as navigation contradicted its own label.

## Why tab URLs retain legacy compatibility

Creator tab paths control persisted bills, while the new-bill route reads the active tab from its query string.

The tab routes set `bill_creator_tab` from their path segment, and that path value remains authoritative even if a query string disagrees. The new-bill reader checks whether `bill_creator_tab` is present before falling back to `tab_key`; an explicitly empty canonical value does not restore the old alias. The legacy `/:id/edit` redirect applies that same key-presence order, removes both tab names from the forwarded query, and maps the old `pipeline_llm` value to the `pipeline` segment. General alias precedence is documented in [[query-parameter-namespaces#Backward compatibility and dual-reading]].

The response prop remains `tab_key` for the existing page contract. Request and URL writers use `bill_creator_tab`, including nested schedule form data and new-page pipeline return links. [[app/controllers/application_controller.rb#ApplicationController#bill_creator_tab_param]] supplies the shared reader, [[app/controllers/bills_controller.rb#BillsController#pipeline_start_back_path]] builds the new-page return address, and [[app/controllers/concerns/bill_creator_tab_redirects.rb#BillCreatorTabRedirects#bill_creator_tab_path]] maps submitted values to persisted-tab paths. Static routes only match supported tab segments, so an unknown segment never renders a tab.

The route table uses explicit tab segments instead of a tab catch-all, and the legacy `/edit` entry remains a redirect so old bookmarks resolve through the same segment mapping. [[config/routes.rb]] owns these route boundaries and [[spec/requests/bill_creator_tab_routes_spec.rb]] pins the supported segments, conflicting query values, legacy alias, and unknown-segment behavior.

## Why a Radix portal is stubbed rather than driven in tests

Both the shadcn `Select` and the combobox render their menus through a Radix
portal, which these component tests cannot see.

Stubbing the control and asserting the contract around it is what keeps the
examples about the component's own behaviour: that the locale selector hands
its callback a number, converting the DOM's string itself, and that the
picker's filtering does what type-to-filter promises. The filter is exercised
through its pure core directly, which covers the matching contract without
fighting portals in a headless DOM.

## Why a feature note opens in a popover

An info icon beside a control carries one sentence saying why that control exists. The sentence opens on hover for a mouse and on a tap for a finger, which is why it is a popover rather than a tooltip.

Radix never opens a tooltip on a touch device, and that is deliberate upstream: a tooltip's whole affordance is a hover, and a finger has none. An operator working the Bill Creator on a phone would therefore meet an icon that does nothing at all. A popover opens from an ordinary click, which is what a tap becomes, and the hover is added on top of that for a mouse rather than relied on.

The two ways in are not the same request, so they part company over focus. A pointer passing across a heading has not asked for the keyboard to follow it, and a hover-opened note leaves focus where it was. A click or an Enter press is a deliberate request to read the note, and that one moves focus into it, which is what a keyboard or screen-reader user needs. The component records which cause opened it and both the opening and the closing focus rules read that record.

The note stays open for a moment after the pointer leaves the icon or the note itself, so the gap between the two is crossable and the sentence survives long enough to be selected. An operator quotes these notes when handing a screen to somebody else — the same reason no surface on these pages sets `user-select: none`, and the reason a pointer that leaves with a button held is treated as a selection drag rather than as a departure.

Where the icon sits is constrained by two things that are invisible until they go wrong. It never stands as a bare child of a row that wraps, because it then lands on a line of its own with nothing beside it and reads as a stray mark; it travels inside a group with the control it explains, and a row that cannot fit both loses the icon rather than the layout. And an icon inside a table's column header would otherwise fold its own label into that header's accessible name, which every cell in the column then announces, so those headers name themselves explicitly instead.

An icon also needs something present to sit beside. One placed against an element that is hidden most of the time is an icon anchored to nothing, which is why the note about a field's draft being held in the browser has no icon at all rather than one floating beside an invisible label.

The sentences live in a registry rather than beside the controls they explain, since the operator reads and edits the whole voice of the four tabs at once. It is split into a module per tab, which is what keeps four sets of hands off one file. Each entry also carries the feature's short name, which is what the icon's accessible name announces.

## Why the Bill form is keyed by bill id

An explicit bill id key on the form guarantees that useForm() rebuilds with a clean state whenever a different bill is active.

The shell already remounts when switching bills, so useForm() resets on its own during ordinary navigation. The explicit key guarantees a fresh form instance even if a visit keeps the component alive across bill changes.

## How the frame adapts to phone browser viewports

Phone viewports use accordions as the primary creator navigation, enforce 44px touch targets on triggers and controls, and wrap picker controls to avoid horizontal overflow.

On narrow screens (down to 320px), picker controls wrap rather than overflowing horizontally, accordion triggers provide active visual styling and >= 44px tap targets, and form actions stick to the top for quick access.

## Why the admin picker queries all bills across sessions

The Bill Creator's picker retrieves unarchived bills across all sessions for the chosen jurisdiction.

This differs from the public `/bills` list, which restricts to the active session. Admin operators need to access historical bills to run pipeline jobs, review past summary changes, or edit metadata regardless of whether the bill's legislative session has concluded. [[bill-session-archiving#Active views]] defines how explicit archives leave the picker and identifier lookups.

## Why the admin picker sorts by introduction date

The picker dropdown orders unarchived bills across sessions by `introduced_date_time_utc` descending, then `external_id` descending, before presenting them to the client.

This remains the default Newest order, matching the public `/bills` list and surfacing the most recently introduced bills first. The separate Recent intro/vote order derives `latest_action_date_time_utc` from the maximum of the persisted introduction, House-vote, and Senate-vote dates; [[app/controllers/bill_creator/picker_bills_serializer.rb#PickerBillsSerializer]] uses that same maximum when scoring picker rows. The derived ISO8601 value reuses dates already fetched for each row and avoids introducing an ingestion field, migration, seeder changes, or backfill. It does not represent committee referrals, hearings, amendments, or signatures. If a row reaches the serializer without any of the three date inputs, the value is nil and the sort places that bill last; persisted bills currently require an introduction date. Newest, A-Z, and Most Interesting remain separate modes, and Newest remains the default.

## Why the picker sort stays in the address

The picker reads its sort mode from the Bill Creator address so links, reloads, and tab changes retain the selected ordering.

`bill_creator_sort` is a registered Bill Creator query parameter. The accepted values are `newest`, `alpha`, `score`, and `latest_action`; missing or unknown values use Newest, and Newest is represented by an absent key. [[app/frontend/components/admin/creator/BillCreatorPicker.tsx#readSortMode]] reads the address and the picker updates it through [[app/frontend/sway_utils/url_navigation.ts#navigateWithParams]]. Centralized navigation carry preserves the registered value when the shell changes tabs, bills, or locales. The picker browser contract in [[spec/system/bill_creator_picker_spec.rb]] also pins sort state alongside a selected run and tab.

## Why the Bill Creator carries query parameters across navigation

The Bill Creator relies on centralized app-wide query parameter navigation carry so operator context persists across tab switches, bill selections, and locale changes.

An administrator working inside the Bill Creator frequently sets query parameters that define the active inspection or execution context, notably `run_id` (which pins the pipeline and summary tabs to a specific pipeline execution) and `sway_locale_id` for jurisdiction scoping. The feature boundary also owns the full inventory of operator controls: `bill_creator_tab` and `bill_creator_sort`, pipeline stage selections (`selected_stages`, with legacy alias `stages`), asset download toggles (`download_missing_assets`), activity log stream filters (`subject`, `severity`, `window`, `cursor`), scheduler release dates (`date`), and one-shot pulse highlights (`highlight`).

Historically, the shell hand-rolled parameter carry using `collectQueryParams` and `withCarriedRunPin`. `collectQueryParams` read `location.search` and merged active URL search parameters directly into outgoing Inertia `visit.data` payloads, while `withCarriedRunPin` appended `run_id` onto destination tab URLs. This duplicate carry caused `run_id` to travel twice per tab switch (both on the URL and in `visit.data`) and leaked arbitrary un-namespaced query parameters across navigation boundaries.

Both helpers were retired in favor of centralized navigation carry (decided in [[query-parameter-navigation-carry#Query parameter navigation carry]]). The shell now dispatches clean `router.visit` calls specifying only component-specific data (such as `{ data: { bill_creator_tab: encodeURIComponent(nextTab) } }`), while the centralized `router.on("before")` interceptor (`app/frontend/sway_utils/queryParamNavigationCarry.ts`) automatically attaches registered query parameters to destination URLs according to `config/query_parameters.yml`. Because the operator controls are registered under the `bill_creator` feature, switching tabs preserves active pipeline stage configurations, asset download toggles, and filter criteria without manual call-site carry.

When an operator deliberately clears a pinned run (such as selecting "Latest run (auto)" in `RunSelector`), `setQueryParamCleared` emits the empty-string cleared signal (`?run_id=`). The centralized interceptor detects this signal and strips the parameter from the outgoing URL, preventing the previous run from resurrecting. Intentional empty list parameters such as `selected_stages=` are preserved to convey explicit zero-stage selections.

## Why a bill save carries its own return tab

The bill update endpoint is shared by the Creator form and the Summary tab, so the request carries the tab that should receive its save response.

Both callers send `return_tab`; [[app/controllers/bills_controller.rb#BillsController#update_return_path]] uses it to redirect to the Summary or Creator route, and [[app/controllers/bills_controller.rb#BillsController#saved_from_summary_tab?]] reads the same value. A referrer cannot reliably distinguish the callers and may be absent.

### Summary saves own their success toast

The Summary editor already announces its successful save, so the controller leaves the redirect without a success flash for that tab.

[[app/controllers/bills_controller.rb#BillsController#update_success_notice]] returns nil when `return_tab` is `summary`. This prevents a second server flash toast from repeating the client confirmation; saves from the Creator form still receive the `Bill Updated` flash.

## Why only the tab container is tested in the shell test

The shell component test isolates navigation and parameter carry logic without mounting heavy tab panel dependencies.

The Bill Creator's four panels (`BillCreatorAccordions`, `BillSchedule`, `BillCreatorPipelineLlm`, `BillCreatorSummary`, `BillCreatorPositions`) each interact with server props, Inertia forms, and real-time ActionCable subscriptions. Mounting the full panel subtree in the shell test would couple shell navigation verification to unrelated panel state and third-party UI widgets.

Instead, the shell test stubs the tab panel interiors with minimal interaction targets, focusing assertions strictly on outgoing Inertia router visits, URL parameters, and unsaved changes confirmation prompts.

Summary descendants such as [[app/frontend/components/admin/creator/BillCreatorTestimonyPositions.tsx#BillCreatorTestimonyPositions]] use the shared confirmation provider for destructive actions. The shell test supplies a confirmation stand-in because the application owns that provider outside the shell; action-specific confirmation behavior belongs to the panel tests.

## Why the unsaved-changes prompt guards every tab

Once the Creator form is dirty every tab is guarded, the Creator tab included, so no tab switch can silently discard an unpersisted edit.

Both the primary Bill Creator form and the Summary tab can edit and persist bill summary content. If an operator makes edits on the Creator form and navigates directly to the Summary tab without saving, those unsaved edits risk being overwritten by subsequent Summary tab actions.

The Creator tab earns its own guard for a second reason. An organization draft entered on the Positions tab lives in the in-memory map held by [[app/frontend/components/admin/creator/context/BillCreatorOrganizationDraftCache.tsx]], which any tab visit unmounts, so a switch back to the Creator tab loses that draft as completely as a switch away from it does.

The guarded set is therefore derived from every member of `ETab` rather than a subset, which also leaves a newly added tab guarded by default.

## Why IPendingNav kind is explicit rather than inferred

The [[app/frontend/components/admin/creator/BillCreatorShell.tsx#IPendingNav]] structure records an explicit kind discriminant so the unsaved changes dialog selects appropriate copy for the requested navigation action.

Inferring the action from a destination URL caused collisions when bill switches and jurisdiction switches shared an identical target address. The explicit discriminant distinguishes bill selections, jurisdiction switches, and pipeline run cancellations without URL pattern ambiguity. The cancellation action omits a target address because server redirection governs where the operator lands.

## Why onBillChange puts both the bill id and the tab in the address

The [[app/frontend/components/admin/creator/BillCreatorShell.tsx#BillCreatorShell]] embeds both the bill identifier and the active tab into the route path so navigation stays on the current tab when switching legislation.

Existing bills expose dedicated tab segments on `/admin/bill_creator/:id/:tab`, keeping the URL canonical without requiring query parameters. The new bill flow lacks a persisted identifier, placing the tab in a query parameter so the server renders the intended panel.

The tab routes supply `bill_creator_tab` defaults, so a direct visit to `/admin/bill_creator/:id/creator` does not need a query parameter for the server to identify the active tab. The page still receives the established `tab_key` prop. Saving the bill returns to that canonical Creator route; the bill id is already in the path, so the redirect does not append tab or bill-id query parameters.

## Why onSwayLocaleChange always returns to the empty picker

Switching jurisdiction navigates back to the empty picker at `/admin/bill_creator/new` because legislation belongs strictly to a single locale.

Retaining an existing bill address across a locale switch would produce an invalid state where the URL references a bill belonging to another jurisdiction. Updating `sway_locale_id` persists the selection in a long-lived cookie, scoping subsequent administrative views to the newly chosen jurisdiction.

## Why onCancelRun is the one place that sends the cancel-run DELETE

A single cancellation handler routes pipeline run deletions through the shell's dirty-form guard before issuing an HTTP DELETE request.

Both the conflict banner and progress components delegate cancellation to this unified handler. Funneling deletions through the shell guarantees that unpersisted form drafts are evaluated before the browser is redirected to the bill associated with the cancelled run.

## Why confirmNav forwards pendingSwayLocaleId explicitly

Confirmation forwards the pending jurisdiction identifier because dialog state holds the unconfirmed selection independently of the route.

Without explicit forwarding during navigation confirmation, visits revert to whichever jurisdiction the server currently resolves, dropping the operator's deliberate choice.

## Why cancelNav resets pendingSwayLocaleId

Canceling navigation clears the pending jurisdiction selection so the picker reverts to the active jurisdiction displayed on screen.

Abandoning a jurisdiction change leaves the operator on the current bill. Resetting the uncommitted state ensures the picker displays the active jurisdiction rather than an abandoned selection.

## Why the unsaved-changes dialog has one sentence per action kind

The confirmation dialog tailors its explanation to the specific action because different navigation actions risk losing different operator state.

Switching bills overwrites browser storage because the form holds draft state for only one bill at a time. Switching jurisdiction returns to an empty picker where subsequent typing replaces the draft. Switching tabs preserves local storage while warning that concurrent saves from other operators could supersede unpersisted text.

## Why the confirm button is not destructive

The confirmation button uses standard button styling rather than a destructive variant because navigating away leaves persisted records intact.

Destructive styling implies permanent deletion of database records. Because client form fields are buffered in browser storage and server data is unchanged, neutral confirmation accurately conveys that only unpersisted field focus is discarded.
