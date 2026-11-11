---
mode: explanation
summary: "The mobile offline SQLite cache's table schema, why purgeAll clears every table on sign-out, and why bills/legislators caches cap rows per locale."
status: agent-extracted
related: [docs/reference/mobile-offline-cache-hook.md, docs/explanation/mobile-bootstrap-lifecycle.md, docs/explanation/mobile-secure-store-key-separation.md]
---

<!-- vale Vale.Spelling = NO -->

# Mobile SQLite cache design

`mobile/src/cache/db.ts` is the single `expo-sqlite` database behind Sway
mobile's offline cache.

The bootstrap response is kept in the `bootstrap_cache` table rather than
in `SecureStore`; `SecureStore` holds only the bearer token and the
session record (see
[Mobile SecureStore key separation](mobile-secure-store-key-separation.md)).

## Tables

| Table | Columns |
| --- | --- |
| `bootstrap_cache` | `user_id` PK + `payload_json` + `fetched_at` |
| `bills` | `id` PK + `locale_id` + `data` + `cached_at` (only the 20 newest per locale) |
| `user_votes` | `bill_id` PK + `data` + `cached_at` |
| `legislators` | `id` PK + `locale_id` + `data` + `cached_at` |
| `prefs` | `key` PK + `value` (preferences held on this device only, such as `selected_locale_id`, which rides along on every API call) |

Index: `idx_bills_locale` on `(locale_id, cached_at)`.

## Why `purgeAll` empties every table

`purgeAll()` empties ALL five tables. Signing out calls it alongside
`bootstrapCache.purge()`, `tokenStore.clear()`, and `sessionStore.clear()`,
so no user data stays behind on the device.

## Why `billCache` caps at 20 rows per locale, in a transaction

`billCache`'s cap is 20 rows per `locale_id`, held in
`MAX_CACHED_BILLS_PER_SWAY_LOCALE`: reads interpolate it into `LIMIT` and
`set()` keeps only the first 20, so the oldest fall off. Writing happens
inside a transaction that first `DELETE`s that locale's rows, so a reader
never catches a half-replaced list.

## Why `legislatorCache` caps at 50 rows per locale

`legislatorCache`'s cap is 50 rows per locale, held in
`MAX_CACHED_LEGISLATORS_PER_SWAY_LOCALE`, which is far more than
needed: a Maryland district has at most 5 representatives, and the federal
level has 2 senators plus 1 representative. A write swaps out all of a
locale's rows in one go.
