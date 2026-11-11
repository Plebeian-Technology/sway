---
lat:
  mode: explanation
---

# Boot failure reporting

A boot that dies of an exception reports nothing by itself. `sentry-ruby` registers only an `at_exit` flush, which sends what is already queued rather than capturing the exception that killed the process, and nothing else in Sway watches for one.

`BootStep.run` is the wrapper that closes that gap: it names the step, catches
`Exception` rather than `StandardError` — a bad require, a missing constant at
load and a signal are all failures that stop a boot dead and none of them
descends from `StandardError` — logs it, hands it to Sentry, and re-raises so the
boot still fails.

## What a silent boot failure costs

Kamal reports a container that never becomes healthy as "target failed to become healthy within configured timeout (10m0s)".

That is ten minutes of nothing, followed by an operator going looking for a real
error that is sitting inside a container which is crash-looping. The wrapper
turns the same failure into one report that names the step and carries the
backtrace, arriving while the deploy is still being watched.

## A missing setting is reported before it stops the boot

`Sway::Settings.build!` raises `MissingValues` when a required value is absent from any settings group, and that raise is inside `BootStep.run("sway.settings")`.

A missing production setting is what a bad secrets push, a renamed environment
variable or a dropped declaration looks like from inside the process, and it
lands one step earlier in boot than the database steps `BootStep` was first
written for. Reporting it is the only thing that changes: the exception still
propagates, so the boot still fails rather than starting with a value nobody
supplied.

## Why the wrapper is required rather than autoloaded

The `sway.settings` initializer runs after `load_environment_config`, and Rails sets the main Zeitwerk autoloader up in its finisher, which is later still.

A constant named in that window resolves only if something already loaded the
file defining it, so `config/application.rb` requires `lib/boot_step.rb` and
`lib/sway_logging.rb` by hand, beside the `lib/sway/settings.rb` require that was
there for the same reason. Left to the autoloader, the reference would raise
`NameError` inside the rescue, `BootStep.report`'s own rescue would catch that
`NameError`, and the boot would end with a `warn` about the reporting rather than
a report of the failure — the one outcome this wrapper exists to prevent.
