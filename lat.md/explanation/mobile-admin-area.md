---
lat:
  mode: explanation
---

# Mobile admin area

How the phone app gives Sway admins an admin area: the drawer entry, the admin stack, the hub screen and the map that decides which tools open on the phone.

## The gate

The server decides who is an admin. The phone only decides whether to show the entry.

`GET /api/v1/bootstrap` carries `is_sway_admin: true` in `current_user` for admins and omits the key for everyone else. [[mobile/src/hooks/useUserProfile.ts#UserProfile]] reads it as `is_sway_admin?: boolean`. A tampered client that shows the entry still meets `verify_is_sway_admin`, which answers a non-admin mobile request with 403 JSON code `forbidden`.

## The drawer entry

The seventh drawer item, labelled Admin with a `ShieldCheck` icon, exists only while `useUserProfile()` reports `is_sway_admin === true`.

[[mobile/src/navigation/AppDrawer.tsx#AppDrawer]] renders the item after the six fixed ones, so their order never changes. The route is named `Admin` in `AppDrawerParamList` and `RootParamList`, and the item carries the test id `drawer-item-admin`. The stack's first route, `AdminHub`, joins the top level route names so the edge swipe opens the drawer from the hub, as on every other stack ([[mobile-tab-navigation-architecture#AppDrawer#Edge swipe opens the drawer only on top level screens]]).

## The admin stack

[[mobile/src/navigation/AdminStack.tsx#AdminStack]] is a native stack shaped like `ProfileStack`, typed by `AdminStackParamList` in [[mobile/src/navigation/types.ts]].

Its first route is `AdminHub`, not `Admin`, because React Navigation warns when a screen sits inside another of the same name, the case [[mobile-tab-navigation-architecture#ProfileStack#Why the main profile screen is named "ProfileHub"]] describes. Admin screens live in `mobile/src/screens/admin/` and register as routes of this stack. A new admin screen adds its route to `AdminStack.tsx`, its params to `AdminStackParamList` and its tool id to the tool map.

## The hub screen

[[mobile/src/screens/admin/AdminHubScreen.tsx#AdminHubScreen]] shows the tools the server sends and the database and queue health numbers.

It carries the brand header with the menu button, like every top level screen. [[mobile/src/hooks/admin/useAdminHub.ts#useAdminHub]] fetches `GET /admin`, which answers JSON to a mobile request ([[admin-hub-index#JSON shape for the mobile app]]). The hook follows `useBill`: state plus an abort guard, returning `data`, `loading`, `error` and `refresh`. Admin data never enters the offline cache. A failed request shows the server's message in an `EmptyState`.

The screen groups tools by `group`, in the web hub's order (Content, Settings, Data) with unknown groups after. Each tool is a `ListRow`. A tool opens only when the map names its id and the tool is not external. Every other tool renders disabled with the description "Not on mobile yet", including the Beszel tool, whose `path` is an absolute URL for a browser.

Database sizes appear as one row per database (database and WAL bytes), followed by the ready and failed job counts.

Read hooks for admin screens live in `mobile/src/hooks/admin/`.

## The tool map

[[mobile/src/screens/admin/adminToolScreens.ts#adminToolScreens]] maps a tool id from `GET /admin` to the name of an admin stack route.

The map starts empty, so every tool shows "Not on mobile yet" until its screen ships. Keeping the map apart from the screen lets the hub show the server's full tool list without importing any tool screen, and lets one edit per tool turn a row from disabled to tappable.

## The shared addresses screen

[[mobile/src/screens/admin/SharedAddressesScreen.tsx#SharedAddressesScreen]] lists the addresses that more than one registered user has given, each with its address id and user count.

The tool id `shared_addresses` maps to the `AdminSharedAddresses` route. [[mobile/src/hooks/admin/useSharedAddresses.ts#useSharedAddresses]] fetches `GET /admin/shared_addresses`, which [[app/controllers/admin/shared_addresses_controller.rb]] answers as `{ shared_addresses: [{ address_ids, user_count }] }` to a mobile request. The screen is read-only and carries no street or coordinate, the same counts-only rule as the web page ([[personal-detail-encryption#Why the shared-addresses admin page reports counts only]]). An empty list shows an `EmptyState`, and a failed request shows the server's message there.

## The user address changes screen

[[mobile/src/screens/admin/UserAddressChangesScreen.tsx#UserAddressChangesScreen]] lists the latest 100 user address switches, one card per switch, with the same fields as the web page.

The tool id `user_address_changes` maps to the `AdminUserAddressChanges` route. [[mobile/src/hooks/admin/useUserAddressChanges.ts#useUserAddressChanges]] fetches `GET /admin/user_address_changes`, which [[app/controllers/admin/user_address_changes_controller.rb]] answers as `{ user_address_changes: [...] }` to a mobile request, serialized by `UserAddressChangeResource` as on the web. Each card shows the user, the switch count, the cross-district, cross-locale and voted-before-switch flags, and the address, locale, district, legislator and prior vote lines. The screen is read-only and carries no street or coordinate. An empty list shows an `EmptyState`, and a failed request shows the server's message there.

## The system prompts screen

[[mobile/src/screens/admin/SystemPromptsScreen.tsx#SystemPromptsScreen]] shows the two models and one expandable row per standing instruction Sway sends the model.

The tool id `system_prompts` maps to the `AdminSystemPrompts` route. [[mobile/src/hooks/admin/useSystemPrompts.ts#useSystemPrompts]] fetches `GET /admin/system_prompts`, which [[app/controllers/admin/system_prompts_controller.rb]] answers with the same props as the web page ([[admin-system-prompts-page#Reading the instructions Sway sends the model]]). A row shows the label, the locale name when the prompt is per locale, and a character count or "Not sent". Pressing the row reveals the purpose, builder, model and the full text as selectable text in a height-capped scroll area; an unavailable prompt shows its reason there instead. The screen is read-only. A failed request shows the server's message in an `EmptyState`.

## The locales screen

[[mobile/src/screens/admin/LocalesScreen.tsx#LocalesScreen]] lists every locale by tier with its user count and lets an admin edit a locale's sample address.

The tool id `locales` maps to the `AdminLocales` route. [[mobile/src/hooks/admin/useAdminLocales.ts#useAdminLocales]] fetches `GET /admin/locales`, which [[app/controllers/admin/locales_controller.rb]] answers with the web page's props to a mobile request ([[admin-locales-registration-visibility#Why one user can count toward three locale rows]]). The screen reads only the id, label, user count and sample address of each row. The summarization and news source blocks stay on the web page.

A row's button opens an inline form of four fields: street, postal code, latitude and longitude. Save sends `PATCH /admin/locales/:id` with a `sway_locale` body of the four values as text, through `useAdminMutation`. A cleared field reaches the server as an empty string, which the controller reads as absent. On success the controller answers `{ sway_locale: { id, sample_* } }`, `AdminLocaleSampleAddressResource`'s key set, and the screen closes the form and reloads the list. A rejected save answers 422 with the model errors, and the form stays open with the server's message under the fields.

## The categories screen

[[mobile/src/screens/admin/CategoriesScreen.tsx#CategoriesScreen]] lists every category with its bill count and lets an admin add, rename, activate, deactivate and delete categories.

The tool id `categories` maps to the `AdminCategories` route. [[mobile/src/hooks/admin/useAdminCategories.ts#useAdminCategories]] fetches `GET /admin/categories`, which [[app/controllers/admin/categories_controller.rb]] answers as `{ categories: [{ id, name, slug, active, bill_count }] }` ([[admin-categories-controller-design#Categories.tsx, the frontend page]]). The controller already answered JSON, so the screen needed no backend change.

The add form at the foot posts `{ category: { name } }` to `/admin/categories`. A row's Rename opens an inline field and saves `{ category: { name } }` with a PATCH. Activate and Deactivate send `{ category: { active } }` to the same path. A 422 shows the server's message under the add field or in the row, as [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]] reads it, and a successful write reloads the list.

The rows follow [[app/frontend/components/admin/categories/CategoryRow.tsx]]. Deactivate and Delete each ask through a native `Alert` with the web page's wording (Deactivate says existing bill assignments are preserved; Delete names the bill count) and send the request only on confirm. Activate sends at once. Delete shows only on inactive rows, because the controller refuses to delete an active category. A 204 resolves `run` to `null` and a refusal to `undefined`, so the row reloads the list only after a successful delete.

## The LLM settings screen

[[mobile/src/screens/admin/LlmSettingsScreen.tsx#LlmSettingsScreen]] shows the model Sway uses for each task and lets an admin change them, with the web page's stale-save guard.

The tool id `llm_settings` maps to the `AdminLlmSettings` route. [[mobile/src/hooks/admin/useAdminLlmSettings.ts#useAdminLlmSettings]] fetches `GET /admin/llm_settings`, which [[app/controllers/admin/llm_settings_controller.rb]] already answered as JSON, so the screen needed no backend change. The screen reads the model lists, the four current models, the two reasoning levels, the batch flag and the last-changed line. It also reads `available_openrouter_models` for [[mobile-admin-area#The LLM model catalog]].

Each of the four models (summarization, classification, decision, extraction) is a row with its current label and a Change button that opens an inline list of the offered models. A model the server marks not selectable shows disabled, and a current model missing from its list shows its raw id. The two Claude tasks show a Low, Medium and High level control only while the chosen model supports reasoning, and choosing a model without that support clears the level. The batch switch is a `PreferenceToggle`.

Save sends `PATCH /admin/llm_settings` with an `admin_setting` body holding only the changed fields plus an `expected` block of the loaded value for each, as [[admin-llm-settings-stale-write-race#Two admins, one LLM settings form#The fix: a per-field baseline and an expected guard]] describes. A null reasoning level travels as an empty string. Save stays off until a field changes.

A 409 shows the mobile copy "Someone else changed these settings. Pull to refresh, then save again." in place of the server's message, which addresses API callers. The screen keys on `errorStatus` from [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]]. Every load, whether a pull to refresh or the reload after a good save, remounts the form from the fresh data, so the draft, the expected block and the error all reset together. Pull to refresh replaces the web page's polling and its changed-elsewhere banner. Any other failure shows the server's message above Save.

## The LLM model catalog

[[mobile/src/screens/admin/LlmModelCatalog.tsx#LlmModelCatalog]] sits below the settings form and ports the web page's Offered Models card: refresh the OpenRouter list, add a model, remove one.

It lists the selectable models of `supported_models`, each with a Remove button. Remove is off for a model in use, meaning any of the four current models or any model chosen in the unsaved form, and off when only one model remains, as on the web page. Adding searches `available_openrouter_models` by label or id, shows the first eight matches, and posts the chosen `model_id` to `POST /admin/llm_settings/add_model`. Refresh posts to `refresh_models`.

A removal sends `DELETE /admin/llm_settings/remove_model` with `model_id` in the query string, because `apiClient.delete` sends no body. The id passes through `encodeURIComponent` since OpenRouter ids contain slashes. Each row owns its own `useAdminMutation`, so the path carries that row's id.

The three endpoints answer the model lists but not `available_openrouter_models`. After a good write the section therefore asks the screen to refetch `GET /admin/llm_settings` instead of reading the answer. The refetch replaces the data without remounting the form, so unsaved choices survive. A 422 shows the server's `error` message beside the control that failed, and nothing refetches.

## The bill summary reports screen

[[mobile/src/screens/admin/BillSummaryReportsScreen.tsx#BillSummaryReportsScreen]] lists the reports readers filed about bill summaries, filtered by status and locale, with a count per status.

The tool id `bill_summary_reports` maps to the `AdminBillSummaryReports` route. [[mobile/src/hooks/admin/useBillSummaryReports.ts#useBillSummaryReports]] fetches `GET /admin/bill_summary_reports` with a `status` query and, when a locale is chosen, a `locale_id` query. [[app/controllers/admin/bill_summary_reports_controller.rb]] answers a mobile request with the web page's props: `reports`, `status_counts`, `locales`, `filter_status` and `filter_locale_id` ([[bill-summary-reporting#Bill summary reporting#Admin triage and remediation]]). The index answered a bare array before, which only its specs read.

Five chips show All, Pending, Reviewed, Resolved and Dismissed with the server's count in brackets. A second row of chips holds All locales and one chip per locale. Choosing a chip refetches with the new query and keeps the other filter. The list stays on screen while the refetch runs. The cards show the bill, locale, reason, the first lines of the reader's details, the reporter and the filing time. The web page's keyword search and its inline Resolve and Dismiss actions are not on this screen. An empty result shows an `EmptyState`, and a failed request shows the server's message there.

Each card is pressable and does nothing yet; the detail screen takes the press over.

## Admin writes

Every admin write goes through [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]], so each screen shows the server's own error message and no screen repeats the request plumbing.

The call is `const { run, loading, errorMessage, fieldErrors, errorStatus } = useAdminMutation<TResponse>("patch", path)`, where the method is `post`, `patch` or `delete`. The client has no PUT and no multipart, and a `delete` sends no body, so a DELETE that needs a parameter carries it in the query string of `path`.

`run(body?)` resolves to the parsed response on success, to `null` when a successful response has no body (a 204 DELETE), and to `undefined` on failure. A screen tells success from failure with `result === undefined`. `run` never throws, so a screen reads `errorMessage` instead of wrapping each call in `try`. Each call clears the previous error first.

- `loading` is true from the start of `run` until the request settles.
- `errorMessage` is the server's message for an `ApiRequestError` (including `NetworkError`), the offline message when the device is offline, and [[mobile/src/api/errors.ts#GENERIC_ERROR_MESSAGE]] for anything else.
- `errorStatus` is the HTTP status of a failed request, or `null`. A screen reads it to replace the server's message for one status, as the LLM settings screen does for 409.
- `fieldErrors` is the error's `details` as the server sent it, or `null`. Its values are `unknown` because real endpoints send arrays, nested hashes, plain strings and arrays of row hashes, so the screen narrows what it reads.
- A screen that needs an extra key of a 422 body (the news article `receipt_status`, for example) reads it from `ApiRequestError.body`, which holds the parsed response body. The hook keeps only the message and field errors.

The hook calls `assertOnlineForWrite` first ([[mobile-offline-cache-hook#Writes must check isOnline first]]), so an offline device sends nothing and `errorMessage` reads "You need a connection to make this change."

Admin endpoints answer `{ error: "some message" }` as often as the `error` object. [[mobile-api-client-contract#Errors]] lists how the client reads each shape, so `errorMessage` carries the endpoint's own words in every case.
