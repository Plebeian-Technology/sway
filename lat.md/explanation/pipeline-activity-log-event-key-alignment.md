---
lat:
  mode: explanation
---

# Why the event-key check runs at boot

`SEVERITY_FOR_EVENT` and `TITLE_TEMPLATES` are two separate constants, each keyed by the same set of event names.

They must name exactly the same events. If one gains an event the other lacks, `emit!` raises a missing-key error the first time that event happens — possibly months later, in production, when nobody is looking at this file.

`PipelineActivityLogger` checks that the two key sets match as soon as the file loads, and raises immediately if they do not. Failing at boot is better than failing the first time a rare event fires: a boot failure is loud and blocks a deploy; a runtime failure is a surprise in a log somewhere.

`legislation_pipeline_run.rb` runs the same kind of check for its own paired constants.

The `PipelineActivityLogEntry` model keeps a third list of allowed event names, and validates against it whenever a row is saved. That check runs at save time, not at boot, because verifying it here would mean loading the model just to run this check.
