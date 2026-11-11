---
lat:
  mode: explanation
---

# Why db/queue_schema.rb needs guarding

Sway keeps background jobs in a second database, and `db/queue_schema.rb` is the ONLY thing in this repo that describes its tables — there is no `db/queue_migrate` folder.

Loading that file is the one and only way those tables ever come into being.

## Why it needs guarding

The file is regenerated automatically after migrations are applied in development, from whatever the job database happens to hold at that moment.

A development machine whose job database was never set up therefore rewrites this file as an empty one — 14 lines, no tables — and nothing says so. It takes seconds and looks like nothing happened.

The cost lands much later and somewhere else: the next machine built from an empty disk gets no job tables, the first thing to ask for a background job dies with `Could not find table 'solid_queue_jobs'`, and the deploy fails ten minutes on saying only that the container never became healthy. That is a whole afternoon between the mistake and the symptom.

## The check and the recovery

`spec/config/queue_schema_spec.rb` compares `db/queue_schema.rb` against the schema Solid Queue itself ships, so an emptied file (or a Solid Queue upgrade that added a table) is reported here rather than on a Pi.

If the file holds no tables at all, it was almost certainly overwritten by applying migrations in development against a job database that was never set up. Restore it with:

```
git checkout -- db/queue_schema.rb
```

If Solid Queue was just upgraded and added a table, regenerate instead:

```
bin/rails generate solid_queue:install
```

## Related: the entrypoint's own job-database repair step

This doc covers `db/queue_schema.rb` going empty in development.

For why `bin/docker-entrypoint` also runs `db:prepare` and `sway:setup_queue_database` against the job database on every PRODUCTION deploy — a different failure mode, a half-made database rather than an empty schema file — see [[docs/explanation/production-snapshot-deploy-rehearsal-harness.md|Why the entrypoint also runs db:prepare and sway:setup_queue_database]].
