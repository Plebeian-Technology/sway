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

The add form at the foot posts `{ category: { name } }` to `/admin/categories`. A row's Rename opens an inline field and saves `{ category: { name } }` with a PATCH; Activate and Deactivate send `{ category: { active } }` to the same path. Delete asks through a native `Alert` and then sends DELETE. A 422 shows the server's message under the add field or in the row, as [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]] reads it, and a successful write reloads the list.

The Delete button shows on every row, not only inactive ones as on the web page, so the server's "Deactivate the category before deleting it." message reaches the admin. A 204 resolves `run` to `undefined`, the same value a failure gives, so the row reloads the list after every delete attempt and keeps its error message. Deactivate sends at once, without the web page's confirmation.

## Admin writes

Every admin write goes through [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]], so each screen shows the server's own error message and no screen repeats the request plumbing.

The call is `const { run, loading, errorMessage, fieldErrors } = useAdminMutation<TResponse>("patch", path)`, where the method is `post`, `patch` or `delete`. The client has no PUT and no multipart, and a `delete` sends no body, so a DELETE that needs a parameter carries it in the query string of `path`.

`run(body?)` resolves to the parsed response on success and to `undefined` on failure. It never throws, so a screen branches on the result and reads `errorMessage` instead of wrapping each call in `try`. Each call clears the previous error first.

- `loading` is true from the start of `run` until the request settles.
- `errorMessage` is the server's message for an `ApiRequestError` (including `NetworkError`), the offline message when the device is offline, and [[mobile/src/api/errors.ts#GENERIC_ERROR_MESSAGE]] for anything else.
- `fieldErrors` is the error's `details` as the server sent it, or `null`. Its values are `unknown` because real endpoints send arrays, nested hashes, plain strings and arrays of row hashes, so the screen narrows what it reads.
- A screen that needs an extra key of a 422 body (the news article `receipt_status`, for example) reads it from `ApiRequestError.body`, which holds the parsed response body. The hook keeps only the message and field errors.

The hook calls `assertOnlineForWrite` first ([[mobile-offline-cache-hook#Writes must check isOnline first]]), so an offline device sends nothing and `errorMessage` reads "You need a connection to make this change."

Admin endpoints answer `{ error: "some message" }` as often as the `error` object. [[mobile-api-client-contract#Errors]] lists how the client reads each shape, so `errorMessage` carries the endpoint's own words in every case.
