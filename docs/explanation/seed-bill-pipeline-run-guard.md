---
mode: explanation
summary: "Why SeedBill's synchronous pipeline run raises loudly on a non-success status, and why the success-status list is memoized instead of a constant."
status: agent-extracted
related: []
---

# Why SeedBill's pipeline run fails loudly, and lazily

`SeedBill#run_pipeline_synchronously!` calls
`LegislationPipelineRunService` with `download_missing_assets:` (the old
`refresh:` kwarg is gone), using the stage list
`LegislationPipelineRun::ALLOWED_PIPELINE_STAGES` (formerly named
`FULL_NON_SUMMARY_STAGES`).

## Fail loudly on a bad run

When the pipeline ended in `:failed` (or any other non-success status), the
seed task used to log a single "pipeline_completed status=failed" info line
and exit 0 — an operator running `dip run rails seed` could easily miss it
and end up with zero new bills. `run_pipeline_synchronously!` now raises
`ServiceUnreachableError` on non-success so the seed task aborts and the
operator sees the failure.

Success means `:completed`, `:succeeded`, or `:partial` (partial = at least
one bill made it through, a legitimate seed outcome). Anything else —
failed, cancelled, or stuck in `:queued` because a state-machine guard hit a
pre-existing failed row — counts as a seed failure.

## Why the success-status list is a memoized method, not a constant

The success-status list used to be a class-level constant referencing
`LegislationPipelineRun::TERMINAL_SUCCESS_STATUSES`. But
`lib/tasks/db_seed_force.rake` loads this file with `require_relative` at
file scope — before the `:environment` task boots Rails — so the constant
lookup ran before Zeitwerk (Rails' autoloader) had loaded the model, and
provisioning aborted with a `NameError`. Memoizing defers the lookup to the
first call, by which time Rails has booted.

## How the isolated-load regression is tested

A normal spec cannot reproduce the `require_relative`-before-boot bug,
because `rails_helper` eager-loads the whole app first.
`spec/db/seeds/bill_isolated_load_spec.rb` instead runs a bare-bones Ruby
boot in a subprocess that imitates the way `db_seed_force.rake` loads
`db/seeds/models/bill.rb`, and checks that no `NameError` comes back.
