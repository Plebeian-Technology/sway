---
mode: explanation
summary: "Explains why Puma needs forked worker processes, not just threads, to use more than one core, with the failure that shows the gap."
status: agent-extracted
related: []
---

# Why Puma needs worker processes, not just threads

`config/puma.rb` scales with `WEB_CONCURRENCY` workers in production and
stays single-process in development. This documents why threads alone
aren't enough, using the failure that makes the gap visible.

## The GVL limitation

Workers are forked *processes*. CRuby's global VM lock (GVL) caps a single
process to roughly one core of Ruby execution — adding more threads to that
one process cannot use a second core for Ruby code. Multi-core throughput
requires more worker processes, not more threads per process.

## What a single process cannot absorb

During a pipeline run, a cable broadcast can trigger a `router.reload` storm
that pegs a single Puma worker at 100% of one core, while other
cores on the box sit idle. The pegged worker starves everything, including
`/up` (which does not even touch the database), until kamal-proxy's gateway
timeout fires a 504.

`WEB_CONCURRENCY` workers let the box spread load across more cores, so a
single flooded worker no longer starves health checks or unrelated user
traffic. See `ops/monitoring/` for the monitoring that watches for this
kind of overload.

Development stays single-process — `WEB_CONCURRENCY` is unset, which
`config/puma.rb` reads as `0` — since a dev box isn't serving concurrent
production-scale traffic.

## Why background jobs don't run inside this web server

Background jobs run in a container of their own — the `job` role in
`config/deploy.yml`, which runs `bin/jobs` — not inside Puma.

`config/puma.rb` keeps a commented-out `plugin :solid_queue` line for
reference. If jobs are ever moved back in-process, do not restore the old
`if ENV["SOLID_QUEUE_IN_PUMA"]` guard around it: nothing sets that variable
any more. It was set in `config/deploy.yml`, read by nothing, and removed
for looking like it did something. A line guarded by it would
silently never run, which is a worse outcome than not having the line.
