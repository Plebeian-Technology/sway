---
lat:
  mode: explanation
---

# Mobile bill creator

How the phone app opens the admin bill creator: the bill picker, the screen that loads one bill per tab, the five tab files and the section components they render.

The web bill creator under [[app/frontend/components/admin/creator]] is the behaviour the phone matches. Its components use Radix, Inertia hooks and the DOM, so the phone cannot import them and ports each part as its own React Native component.

## The bill picker

[[mobile/src/screens/admin/billCreator/BillPickerScreen.tsx#BillPickerScreen]] lists the bills of the current locale, filters them as the admin types and opens one in the bill creator.

The hub tool id `bill_creator` maps to the `AdminBillPicker` route ([[mobile-admin-area#The tool map]]). [[mobile/src/hooks/admin/useBillPicker.ts#useBillPicker]] fetches `GET /admin/bill_creator/new` and reads its `bills` prop, the list the web picker shows. [[app/controllers/bills_controller.rb#BillsController#new]] answers that page through `render_inertia_or_json`, so a mobile request gets JSON and the web still gets the Inertia page. A mobile request that names no tab gets only `bills` ([[mobile-bill-creator#Each tab gets only its own props]]).

The search field keeps a bill when its external id or its title contains the typed text, ignoring case. The web picker also matches the sponsor, status, chamber and category, and offers four sort orders; the phone keeps the server's Newest order. Each row shows the external id with the title below it. A New bill row sits above the list and stays visible while a search matches nothing.

Pressing a bill pushes `AdminBillCreator` with that bill's id. Pressing New bill pushes it with `billId: null`.

## The bill creator screen

[[mobile/src/screens/admin/billCreator/BillCreatorScreen.tsx#BillCreatorScreen]] shows one bill, or a new one, with a `SegmentedControl` for the tabs Creator, Schedule, Pipeline, Summary and Positions.

The screen opens on the Creator tab. [[mobile/src/hooks/admin/useBillCreator.ts#useBillCreator]] takes the bill id and the tab, and fetches the tab's own path: `GET /admin/bill_creator/:id/<tab>` for a saved bill, which [[app/controllers/bills_controller.rb#BillsController#edit]] answers as JSON, and `GET /admin/bill_creator/new?bill_creator_tab=<tab>` for a new one. Changing the tab fetches again. The hook follows `useBill`: state plus an abort guard, returning `data`, `loading`, `error` and `refresh`, and nothing enters the offline cache.

The header shows the bill's external id and title from the loaded `bill` prop, or "New bill". A failed request shows the server's message in an `EmptyState`, and pull to refresh reloads the current tab.

### A tab never sees another tab's props

Each tab may receive a different set of props from the server, so the hook clears its data when the bill or the tab changes and the screen shows a spinner until the new answer arrives.

A tab therefore renders only from the answer to its own path. Pull to refresh keeps the current data on screen, because the tab does not change.

## Each tab gets only its own props

For a mobile request, the bill creator answers with only the props the requested tab reads, listed per tab in [[app/controllers/bills_controller.rb#BillsController#BILL_CREATOR_TAB_PROPS]].

The web tabs poll every five seconds, and a mobile tab polls its own path the same way. The web page builds every tab's props on each request, and the omission header ([[lazy-inertia-props#Mobile JSON omission is an explicit request]]) drops only a few named optional props. Without the map, every poll would rebuild the whole creator: the vote-entry roster, every organization, the activity log and the fetched-bills scan of the disk. [[app/controllers/bills_controller.rb#BillsController#mobile_bill_creator_tab_props]] slices the prop hash before resolution, so a prop outside the tab's list never runs. Web requests keep every prop.

Each list comes from the web components that tab renders. [[app/frontend/components/admin/creator/BillCreatorShell.tsx#BillCreatorShell]] picks one root component per tab, and the list holds the page props read anywhere below that root:

- Every tab gets `bill` and `bill_id`.
- Schedule adds `bills`, because its calendar and sidebar place every bill of the locale on their dates.
- Creator and Positions both render the organizations panel, so both carry `organizations` and `tab_key`, which the panel sends back on save.
- Pipeline carries the keys that [[app/controllers/bills_controller.rb#BillsController#edit]] adds outside the shared prop builder: the activity log, the artifact mirrors and the fetched bills. The web pipeline poll list also names `testimony_claimed_affiliations`, but nothing on that tab reads it, so the mobile list leaves it out.
- Summary carries `review_draft_revision`, which reads the `draft_revision_id` query parameter, so a summary request still answers the draft named in its address.

[[app/controllers/bills_controller.rb#BillsController#new]] applies the same lists to a new bill. With `bill_creator_tab=<tab>` it answers that tab's keys, less any key a new bill has no builder for. With no tab, or a name the map lacks, it answers [[app/controllers/bills_controller.rb#BillsController#BILL_PICKER_PROPS]], which is what the picker reads. The props the web marks optional and never builds for mobile, such as the summary prompt and the campaign letter text, stay absent whatever the tab.

A mobile section that needs another prop adds the key to its tab's list.

## The tabs

Each tab is one file in [[mobile/src/screens/admin/billCreator/tabs]], and the screen picks the file for the selected tab from a fixed map.

The screen passes every tab the same props, [[mobile/src/hooks/admin/useBillCreator.ts#BillCreatorTabProps]]: the bill id (`null` for a new bill), the loaded data and `refresh`. A tab reads only the props it needs. Every tab file starts as an `EmptyState` saying the tab is not on mobile yet.

## Sections

A section is one part of a web tab, ported as a component in `mobile/src/components/admin/billCreator/` and rendered by its tab file.

Porting a section adds its component to the tab file and a short section to this document describing it. Writes go through [[mobile/src/hooks/admin/useAdminMutation.ts#useAdminMutation]] ([[mobile-admin-area#Admin writes]]).
