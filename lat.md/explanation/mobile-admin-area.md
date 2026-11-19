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
