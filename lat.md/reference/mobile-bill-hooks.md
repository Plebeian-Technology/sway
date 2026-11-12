---
lat:
  mode: reference
---

# Mobile bill hooks

Contract for useBill, usePublicTestimonyLetters and the useBills.ts hooks (useBills, useBillCategories) — what each loads, and how caching is split between them.

## useBill

`useBill` (`mobile/src/hooks/useBill.ts`) loads one bill from `/bills/:id?with=legislator`. The same Rails endpoint answers both the website and this app.

- Two callers: `BillDetailScreen`, and the featured-bill screen's keyed body, `BillOfTheMonthBody`, whose bootstrap payload carries only the bill's own fields ([[mobile-bill-detail-and-bill-of-the-month-screens#BillOfTheMonthScreen's data source quirks]]).

- You get back the page payload the website would receive, as JSON, minus the omitted keys below. The keys: `bill`, `sponsor`, `user_vote`, `bill_score` (whose `districts` rows are the per-district tallies), `districts` (the reader's own districts), `organizations` and `organization_bill_positions` (the same rows under two names), `public_testimony_counts` (null for a signed-out reader) and `legislator` (the reader's first legislator in the locale, present because of `?with=legislator`). A signed-in reader with legislators on an active bill also gets `email_preview` and `user_legislator_emails`.

- The screens read `bill`, `sponsor`, `user_vote`, `bill_score`, `districts`, `organizations` and `public_testimony_counts`; the other keys go unread on the phone.

- Every request sends `X-Sway-Omit-Props: legislators,legislator_votes,public_testimony_letters` ([[lazy-inertia-props#Mobile JSON omission is an explicit request]]). `districts` is not named, because [[mobile-bill-surface-components-design#DistrictVotesPanel]] needs the reader's districts to find their own; the letters are fetched separately and only on demand.

- On purpose, this hook does not paint from the on-device cache the way the bill-list hook `useBills` does. One bill's detail belongs to one screen, and it is kept current by background polling and live WebSocket updates instead. There is an offline copy of a single bill, `billCache.get(id)`, and `BillDetailScreen` could start using it later to show the old copy at once and refresh behind it. For now the behaviour is: fetch when the screen opens, refresh on each poll or live update. That matches the website's `Bill.tsx`, which refreshes the same way.

- Cancelling: the request carries an abort signal that `apiClient` honours, so flipping quickly between tabs cancels the request already in flight instead of updating a screen that is gone. The resulting "aborted" error is ignored on purpose.

## usePublicTestimonyLetters

`usePublicTestimonyLetters(billId, { enabled })` (`mobile/src/hooks/usePublicTestimony.ts`) loads a bill's browsable constituent letters, and only while `enabled` is true.

- It requests `GET /bills/:id/public_testimony_letters`, which answers with the array of letters alone, or `null` for a signed-out reader, and reads `null` as no letters. It sends no `X-Sway-Omit-Props` header and no `?with=legislator`.
- It returns `letters` (null until they load), `loading`, `error` and `refresh`.
- A letter is `{ position, label, stance, body_text }`. A row whose `position` is not a number or whose `body_text` is not a string is dropped, and a stance other than support or oppose becomes neutral.
- Turning `enabled` off clears the state and makes no request; turning it on fetches, and a different bill id fetches again. Disabling or unmounting aborts the request in flight.
- A refresh keeps the letters already loaded for the same bill while it runs, and never shows another bill's letters.
- The only caller is [[mobile-bill-surface-components-design#PublicTestimonySection]], which enables it while its sheet is open.

## useBills

`useBills(localeId, options)` (`mobile/src/hooks/useBills.ts`) loads the bill list for a locale, serving the cached copy immediately on default queries before fetching fresh data.

- It stitches together `billCache` (the on-device store), `apiClient`, `Routes.bills()`, and `Routes.pastBillsOfTheMonth()`. When `options.listMode === "past_bills_of_the_month"`, it queries `/past_bills_of_the_month`; when `options.legislativeSessionId` is provided in `"all_bills"` mode, it appends `bills_legislative_session_id` and returns `legislativeSessions` and `selectedLegislativeSessionId` from the response. Non-default queries bypass the single-slot per-locale `billCache` so historical or featured-only lists do not overwrite the cached current-session list.

- `BillRecord` is loosely typed: the server's fields change over time, so screens read only the keys they know.

- Three app-wide rules meet here: anyone may browse without signing in, saving anything needs a live connection, and lists always paint from cache first.

- It reads and writes `billCache` itself and does not call `useOfflineCache`; it borrows only that hook's `UseOfflineCacheResult` return type.

- The query parameter must be named `sway_locale_id`, not `locale_id`: that is the name the Rails side reads when it works out which place is being asked about. Send the wrong name and the server quietly falls back to the user's home place, so the picker looks broken and reports "no bills found".

## useBillCategories

`useBillCategories(localeId)` is the list of category chips shown above the bill list. The names come from the server, in the `all_categories` field of the `/bills` response.

- [[mobile/src/hooks/useBills.ts#useBills]] captures `all_categories` into [[mobile/src/hooks/useBills.ts#capturedCategoriesByLocale]] and tracks active requests in [[mobile/src/hooks/useBills.ts#inFlightBillsRequests]] so [[mobile/src/hooks/useBills.ts#useBillCategories]] reuses the in-memory list or attaches to an in-flight request before falling back to a standalone `/bills?sway_locale_id=N` GET. If the network request fails, the hook leaves the chip list empty because category chips are optional filter affordances.
