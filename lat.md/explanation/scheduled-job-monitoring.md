---
lat:
  mode: explanation
---

# Scheduled job monitoring

A recurring job that fails every time it runs is a standing state, not an event, and Sentry's error grouping cannot express that. A cron monitor can, so scheduled jobs whose silence would go unnoticed check in against one.

`ReplicationLagCheckJob`, `RefreshLegislatorsCacheJob` and `BackupLegislationArtifactsJob` carry one each ([[legislation-artifact-backup#Why the scheduled backup carries a cron monitor]]).

## A monitor is watched only when it is enabled and has a recipient

Each of the three jobs sends check-ins to its own Sentry cron monitor, but Sentry processes a check-in only for an enabled monitor.

A failed or missed run of a job whose monitor is disabled is visible only as an error event, and in the local failure record described below.

A red monitor is a dashboard state, and a dashboard nobody opens is no better than the error grouping it replaced. An enabled monitor therefore needs a person to notify: the monitor's own settings send a failed or missed check-in to a named recipient, rather than relying on the project issue alert rules, which fire on new and high-priority issues and were never checked against a cron failure.

## A replication stall needs the copier's position as evidence

The planned stall diagnosis compares the accessory's database path and transaction stream with the monitor's persisted position. A repeated alarm proves lack of observed progress, but does not alone identify which side is wrong.

ReplicationLagCheckJob writes its heartbeat on every check, so an idle
application is insufficient explanation for a healthy replica never advancing.
Accessory logs, remote positions and the primary heartbeat together distinguish
a stopped copier from a path mismatch or an obsolete position. Resetting the
heartbeat or suppressing the alert before that comparison would erase evidence.

## Why a cron monitor and not another error report

Repeated failures of a weekly job such as `RefreshLegislatorsCacheJob` do reach Sentry. Being reported is not the problem; being legible is.

Sentry groups identical errors, so successive failures arrive as one issue holding several events — a shape indistinguishable from a transient fault that has already stopped. A run that raises a differently worded error from a different line opens a new issue with nothing tying it to the earlier ones, and an issue can read `resolved` while the job remains broken.

None of this is a defect in error reporting. An error event answers *did something go wrong at this moment*, and each one answers it correctly. The unanswered question was *is this job working*, and no accumulation of error events answers it, because a job that has silently stopped being scheduled at all emits nothing to accumulate.

A cron monitor holds the answer as state. It goes red when a run fails or fails to arrive, and only a successful check-in returns it to green — so a fix that does not work cannot close it, and the following Sunday reopens it.

## Why the slug is written out rather than derived

`MONITOR_SLUG` is passed explicitly, though `sentry-ruby` would otherwise derive one from the class name.

A derived slug is a rename hazard. Renaming the job would silently create a second monitor in Sentry and strand the first one, taking its history and any alert rules attached to it out of view, with nothing in the diff to suggest it had happened.

## The crontab constant has to match the schedule file by hand

`MONITOR_CRONTAB` and the `schedule` under `refresh_legislators_cache` in the production block of `config/recurring.yml` describe the same thing twice, and nothing in the library reconciles them.

A disagreement between the two is quiet and misleading in both directions: the monitor waits for check-ins at times the job never runs and reports them missed, or it waits so loosely that a genuinely missed run looks punctual. Each monitored job therefore carries a spec that loads `config/recurring.yml` and compares the schedule it finds there against the monitor's own crontab, which turns the duplication into a red test rather than a silent drift.

## Why a weekly job gets an hour of margin

`MONITOR_CHECKIN_MARGIN_MINUTES` is how late a check-in may be before Sentry calls the run missed, and 60 minutes is generous against a schedule measured in weeks.

The margin absorbs ordinary delay rather than concealing failure. A worker draining a backlog, a deploy overlapping the scheduled minute, or a queue polling interval can each push the start past 03:00 on a Sunday without anything being wrong. A late run still checks in and still turns the monitor green; the margin only decides how long Sentry waits before concluding that no run is coming.

It is deliberately far shorter than the interval it guards. An hour of slack on a weekly schedule cannot hide a skipped week, which is the condition the monitor exists to catch.

## Why RefreshLegislatorsCacheJob rescues each locale independently

Each locale's refresh runs inside its own rescue, so one flaky upstream source never stops the other locales from refreshing.

Baltimore's Legistar feed, OpenStates, and Congress's API are three independent upstream sources with independent uptimes. A single rescue around the whole loop would let one down source cost every other locale its weekly refresh, so the isolation sits at the per-locale boundary where the independence actually lives. Each caught exception is logged and reported to Sentry with the locale's name attached, and the loop moves on to the next locale rather than propagating.

## Why a total-failure run reports rather than fails

A run in which every attempted locale raised is indistinguishable, from the outside, from a genuinely quiet week where nothing changed — unless something inside the job says otherwise.

The per-locale rescue swallows every exception so the loop can continue, which leaves `changed_files` empty and sends the run down the no-changes branch whether the week was quiet or nothing was ever reached. Without a separate signal, a total failure is silent.

`ALL_LOCALES_FAILED_ALARM` is sent with `Sentry.capture_message` after the loop, once at least one locale was attempted and every attempted locale raised. The comparison is `failed_count == attempted_count`, counted only over locales the run actually attempted, rather than against a fixed number — the set of supported locales is expected to grow, and a comparison against today's count would silently stop meaning "all of them" the day a fourth locale is declared. A locale skipped because it declares no refresher (`refresher_for` returning nil) never increments `attempted_count`, so a week in which every locale is genuinely undeclared stays the ordinary quiet case.

The job reports rather than raises. The trade-off is recorded here because it is invisible from the code: the job returns normally after sending the message, so this job's Sentry cron monitor still records the run as successful. A total failure is therefore a message in Sentry rather than a red monitor, and the monitor stays green — which is the condition `docs/explanation/replication-lag-check-job-design.md` calls out as a deliberate decision. The alarm text is a frozen constant so the events group together across runs rather than fragmenting on a varying string.

The individual locale exceptions are untouched by this: each is still caught, logged, and reported separately, so the message says how many locales were attempted and the per-locale events carry the reasons.

## Why a job that sends real messages is scheduled in production only

The voting reminder is registered under `production:` alone, on the default queue.

It sends real text messages to real phone numbers, so a development or test
machine running it on a schedule would reach people who never asked to hear from
that machine. The job itself was finished and covered by specs long before
anything scheduled it, which is the failure the schedule's own spec exists to
catch: a job nothing invokes looks exactly like a job that works.

## Every entry names schedule, and every schedule is a UTC cron string

Two conventions hold across the whole recurring file: the key is `schedule:`,
never `cron:`, and its value is a five-field cron string fixed to UTC.

The key matters because the job runner registers only entries carrying a
`schedule:` key. An entry keyed `cron:` is dropped in silence and never fires,
which looks identical to a job that runs and does nothing — so the rule is
worth stating at every entry rather than discovered once.

The value is a cron string because the schedule parser ignores timezone tokens
in natural-language schedules: writing an hour with a zone name yields a
schedule that does not mean what it says. Fixing the hour in UTC accepts an
hour of daylight-saving drift, which the off-peak windows are wide enough to
absorb.

Which environment an entry belongs to follows from what it touches. A job that
reaches external services, sends real messages, opens pull requests, needs a
cloud key, or watches a replica the machine does not have belongs under
production alone; a pure database sweep with no external coupling runs in
development too, and the development queue is better for it.

## Where a failed run is recorded on this side

A run that fails for good, with no retry rule or after its retries are exhausted, is held in the queue database's `solid_queue_failed_executions` table with its exception class, message and backtrace.

The job row beside it names the class and arguments, so the failure can be read without the log.

An attempt that is going to be retried reaches neither that table nor Sentry. Solid Queue re-enqueues it instead of recording a failure, and `active_job_report_on_retry_error` is off in the Sentry initializer so that one fault does not become a burst of identical events. The `job_fail` line that `ApplicationJob` writes to the Rails log is the only trace of such an attempt.

A run that never started leaves no row at all. Solid Queue's recurring bookkeeping records only the runs it enqueued, and a scheduler that starts after a missed tick schedules the next one rather than the one it missed. The only record of a missed run is the monitor's missed state, which Sentry sets once the check-in margin has passed, and only for an enabled monitor.
