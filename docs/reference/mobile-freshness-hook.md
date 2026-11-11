---
mode: reference
summary: Contract for useFreshness — how it derives "Last synced HH:MM" from SQLite, its bootstrap_cache column-name exception, and its relationship to the web hook of the same name.
status: agent-extracted
related: []
---

# useFreshness hook

`useFreshness` (`mobile/src/hooks/useFreshness.ts`) works out the "Last
synced HH:MM" line by looking at when the rows in one on-device table were
last saved.

It runs `SELECT MAX(cached_at) FROM <table>`, which is the newest save time
in that table. The `bootstrap_cache` table names that column `fetched_at`
instead, so it reads `MAX(fetched_at)` there. It hands back that time as a
`Date`, together with the `isRevalidating` flag the caller passes in — the
caching layer turns that flag on while it is quietly refetching in the
background.

This is the mobile version of `app/frontend/hooks/useFreshness.ts`, which
reads the browser's Cache API instead. When the table is empty,
`lastSynced` comes back as `null` so the freshness label can hide itself on
a first-ever launch.
