---
mode: explanation
summary: "Explains why record_failure re-reads the row's committed status before writing an error, and why its own Activity Log write is itself rescued."
status: agent-extracted
related: []
---
# Why record_failure re-checks status and rescues its own logging

<!-- vale Vale.Spelling = NO -->

## The write and the transition are gated together

`GenerateBillSummaryJob#record_failure` used to write `generation_error`
UNCONDITIONALLY while only transitioning the row when it was
`generating`. Any exception raised on a non-generating row therefore
tagged it with an error and left its status alone — which is precisely
how a COMPLETED row acquired a `generation_error` that did not come from
the positions rescue, breaking the rule that rescue's own documentation
asserts and `LlmSummaryPositionsErrorNotice` relies on (see
[bill-summary-positions-error-handling.md](bill-summary-positions-error-handling.md)).
The trivially reachable case is a raise from the success log line
immediately AFTER `mark_completed!`; the `mark_completed!` raise itself
was the expensive one.

The write and the transition are now gated together: an error that
arrives after the row is terminal is LOGGED (an operator still needs to
see it) but does not relabel a settled row.

### The gate itself needed the same fix as everything else in this file

A later review found the gate read `generation_status` off the IN-MEMORY
record, and nothing on the ordinary path reloads it — the only `reload`
in `#perform` lives inside the positions rescue. On exactly the race this
file makes reachable elsewhere (`RunLegislationPipelineJob`'s inline
`perform_now` racing a queued job — see
[bill-summary-arm-row-ownership.md](bill-summary-arm-row-ownership.md)),
the gate read the stale value `"generating"` while the row was already
`completed`, wrote `generation_error` onto it, and flipped it to
`failed` — relabelling a paid-for, persisted summary as a failure and
putting a non-positions error on a completed row. The gate is now a
re-read of COMMITTED state under the write lock; see
`#settle_under_lock`.

The rule this enforces: put a failed model call in the operator's
Activity Log, and never let doing so replace the failure it is
describing.

## Why the Activity Log write exists

`#record_failure` writes `generation_error` onto the row, which the Bill
Creator shows for THAT bill. Nothing reached the Activity Log. Inside a
pipeline run, the stage failure gets logged, but a summary regenerated
from the bill's own screen is not inside a run — so the one place an
operator goes to ask "what has this system been doing" said nothing about
a call that was paid for and produced nothing.

### Why a failed model call can write two separate Activity Log entries, not one

A transport failure and a schema failure mean different things to the
operator, and their next move differs: a transport failure is wrapped
`TransientBillSummaryError` and will be retried by the job on its own, no
action needed; a schema failure is wrapped `DeterministicBillSummaryError`
and `discard_on` drops it, so it will NOT be retried and somebody has to
look. Logging them as two distinct entries, rather than collapsing to one
generic "summary call failed" line, is what lets the Activity Log tell an
operator which of those two situations they are looking at.

## Why the Activity Log write is itself rescued

`log_llm_failure`'s caller is about to re-raise a wrapped error that
decides whether the job retries. Writing a log row is another write to
the same busy SQLite database, and if it raised here it would replace
that error with its own — turning a retryable transport failure into an
unrelated database error, and losing the reason. A log entry is worth
having and never worth that.

The bill is handed to `#log_llm_failure`'s block as an argument rather
than read from a closure, so the nil guard at the top of the method is
what the block's argument type comes from. Reading from the closure, it
would stay nilable at every call site, each needing its own guard for a
question already answered here. Inside the rescue that wraps the yield,
`bill&.id` (not `bill.id`) is needed again even though the guard already
returned for a nil bill: a rescue clause starts a fresh branch, so that
earlier narrowing does not reach it.

## settle_failure!: the settle may not replace the error it was called to record

Every caller of `#record_failure` raises `error` on the next line, and the
retry policy — `retry_on` for transient, `discard_on` for deterministic —
hangs off ITS class. An exception escaping from `#settle_failure!` becomes
the job's outcome instead, so a deterministic failure could start
retrying and a transient one could stop. `#settle_under_lock` already
makes this promise for the one case it knows (a row deleted mid-flight);
the promise belongs to the whole settle, so `#settle_failure!` rescues its
own `with_lock` block.

It became reachable when this settle started finishing a deferred paste
hand-off: the hand-off writes, so it can hit `SQLITE_BUSY` like
any other write. The raise rolls the whole `with_lock` transaction back,
so the row is left exactly where the paste left it — in flight,
reclaimable, and settleable by the retry's supersede gate or by the sweep.
That is the outcome the paste hand-off rule asks for (see
[bill-summary-paste-hand-off-rule.md](bill-summary-paste-hand-off-rule.md)).
