---
lat:
  mode: explanation
---

# Mobile SQLite cache design

The mobile app relies on a local SQLite database for offline storage of bootstrap data, cached bills, cached legislators, user votes, and preferences.

The database is managed via `expo-sqlite` through `mobile/src/cache/db.ts`.

## Tables and schema layout

The cache database comprises five dedicated tables storing offline entities and device preferences.

`bootstrap_cache` stores bootstrap payloads per user; `bills` stores recent bills per jurisdiction; `user_votes` stores votes; `legislators` stores legislators per jurisdiction; and `prefs` stores local preferences such as `selected_locale_id`.

## Why purgeAll empties every table

`purgeAll` clears all five tables on user sign-out to guarantee that no user data remains on the device.

Signing out invokes `purgeAll()` alongside token clearing, while `wipeLocalCaches` invokes `clearCapturedCategories()` to reset in-memory captured bill categories and legislative session options, ensuring that subsequent unauthenticated or different user sessions start from a clean state.

## Why billCache caps rows per locale in a transaction

`billCache` limits cached bills to the newest entries per jurisdiction to bound database growth.

The cap is defined by `MAX_CACHED_BILLS_PER_SWAY_LOCALE`. Writes execute within a SQLite transaction that deletes previous rows for that jurisdiction and inserts fresh rows atomically, preventing readers from observing partial updates.

## Why legislatorCache caps rows per locale

`legislatorCache` bounds cached legislators per jurisdiction with atomic replacement.

The cap in `MAX_CACHED_LEGISLATORS_PER_SWAY_LOCALE` accommodates local and federal delegation sizes while replacing the jurisdiction's entries in a single write.

## Why useLegislators reads and writes legislatorCache per locale

`useLegislators` checks `legislatorCache` before issuing network requests, serving cached representatives immediately while updating local storage asynchronously upon successful response.

Local SQLite retrieval provides instantaneous UI transitions when switching jurisdictions or opening the app offline. To protect against unbounded storage growth, writes maintain the `MAX_CACHED_LEGISLATORS_PER_SWAY_LOCALE` constraint through an atomic delete-and-replace transaction for the target locale.

## Why address changes evict mobile SQLite caches

Updating an address clears captured categories, cached bills, and cached legislators before refreshing bootstrap data.

Changing a constituent address in `AddressScreen` alters electoral district boundaries and representative assignments across city, state, and federal jurisdictions. Retaining cached legislator rosters or bill lists would expose constituents to mismatched representative data. Upon successful submission, the screen calls `clearCapturedCategories()`, `legislatorCache.clear()`, and `billCache.clear()` across the `legislators` and `bills` tables before refreshing bootstrap data from the server.

## Why vote submission evicts the target bill's locale cache

Recording a vote invalidates the target bill and cached legislators in SQLite to reflect updated score and voting state.

When `useCastUserVote` successfully records a user vote, it calls `billCache.clearOne(billId)` to evict the voted bill from `bills` and `legislatorCache.clear()` to clear the `legislators` table so stale representative alignment scores are not hydrated from SQLite on subsequent visits.
