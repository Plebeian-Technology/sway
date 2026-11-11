---
lat:
  mode: explanation
---

# Why the integrity check initializer is a thin hook

`config/initializers/sqlite_integrity_check.rb` runs SQLite's `PRAGMA quick_check` (a fast corruption scan) when the web server boots.

This file is only a thin hook: the real logic lives in `lib/sqlite_integrity_check.rb` so tests can exercise each environment's branch without restarting Rails. That module's docstring describes what happens in each environment.

The `after_initialize` block guards `SqliteIntegrityCheck.run` with [[lib/sway/boot_enqueue.rb#BootEnqueue|Sway::BootEnqueue.web_server_process?]] (see [[boot-time-backfills#Only the web server process enqueues]]) so the corruption scan runs once when the Puma web server starts and is skipped in one-shot deploy Rake tasks, console sessions, and the Solid Queue job runner (`bin/jobs`). Skipping non-server processes avoids scanning the full production SQLite database five extra times during deploy Rake tasks and prevents faulting the database file into the job container's cgroup page cache at startup.
