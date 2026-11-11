---
lat:
  mode: explanation
---

# Why config/queue.yml polls an ordered queue list, not a wildcard

The single Solid Queue worker used to poll `queues.

The single Solid Queue worker used to poll `queues: "*"`, so one slow `background` job (pipeline, sweep, or summary work) could starve the jobs users are actively waiting on in `default` (SMS delivery, registration, native push, voting reminders). The worker now polls an ORDERED list, `[default, background]`, so `default` empties first before the worker ever looks at `background` work.

## Why every real ApplicationJob's queue is checked against the poll list

A job enqueued onto a queue that no worker polls sits there forever with no error — nothing fails loudly, the job just never runs.

`spec/config/queue_spec.rb` guards against this drift by eager-loading the app and checking that every non-abstract `ApplicationJob` subclass's `queue_name` appears somewhere in the worker's queue list.

The check is scoped to classes whose source lives under `app/`: `sentry-rails` defines `Sentry::SendEventJob` as an `ApplicationJob` subclass with a lambda-computed queue name, but Sway never enqueues it (`config.async` is unset), and a gem's own queue choice is not drift Sway needs to guard against.
