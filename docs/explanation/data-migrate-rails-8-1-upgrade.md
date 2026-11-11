---
mode: explanation
summary: "Why data_migrate was upgraded from 9.4.2 to 11.x: two bugs on Rails 8.1 that crashed real deploys while the rehearsal harness stayed green."
status: agent-extracted
related: [docs/explanation/production-snapshot-deploy-rehearsal-harness.md]
---

# Why data_migrate is pinned to 11.x, not 9.4.2

<!-- vale Vale.Spelling = NO -->

`ProductionSnapshot.migrate!` (the deploy-rehearsal harness) replays the
same migrations a deploy runs, but it calls
`DataMigrate::DatabaseTasks.run_migration` directly rather than going
through the `db:migrate:with_data` rake task that `bin/docker-entrypoint`
actually invokes on the production server. That gap hid two separate
breakages in `data_migrate` 9.4.2's own rake task on Rails 8.1:

1. The rake task handed out a database connection Rails had already
   removed.
2. It passed database configs where Rails 8.1 expects an environment name,
   which made it quietly count zero pending schema migrations.

Every deploy attempt crashed while the rehearsal stayed green, because the
rehearsal never went through the real rake task at all. Upgrading
`data_migrate` to 11.x, which supports Rails 8.1 directly, fixed both
breakages; the Gemfile now pins `data_migrate ~> 11.3`.

`spec/production_readiness/production_migrate_with_data_task_spec.rb`
closes the coverage gap this exposed: it shells out to the real
`db:migrate:with_data` rake task in a separate process, in the production
environment, against a throwaway copy of the snapshot, so a broken task can
never hide behind a passing rehearsal again.
