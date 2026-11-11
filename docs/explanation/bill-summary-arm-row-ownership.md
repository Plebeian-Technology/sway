---
mode: explanation
summary: "Explains how arming a bill-summary provisioning row claims ownership under a lock so two concurrent runs cannot double-charge or overwrite each other."
status: agent-extracted
related: []
---
# Arming the provisioning row without stepping on another run

<!-- vale Vale.Spelling = NO -->

`GenerateBillSummaryJob#arm_row_unless_owned!` decides whether an
execution may go on to make paid LLM calls. It is held to the same rule
as every settle in this file: decide from COMMITTED state under the
write lock, not from the copy `#perform` loaded.

## The race this method exists to close

This used to be two bare lines: `enqueue! if can_enqueue?` and
`start_generating! if can_start_generating?`. `state_machines` validates a
transition against the IN-MEMORY attribute (the same fact
`#settle_completed`'s own documentation records — see
[bill-summary-settle-completed-guard.md](bill-summary-settle-completed-guard.md)),
and nothing between the row load at the top of `#perform` and those two
lines reloaded it.

On the race this makes reachable —
`RunLegislationPipelineJob#execute_bill_level_service` calls
`#perform_now` inline, bypassing `GenerateBillSummaryService`'s locked
`pending?`/`generating?` guard — a queued job whose copy still said
`pending` wrote `generating` over a row another execution had already
bought and settled `completed`. It then cleared that execution's
`summary_run_id`, bought both adapter calls a second time, and overwrote
its summary, breakdown, citation verdict, and `llm_generated_at`. One
operator click, two full-price generations, and the output of the run
that finished first was destroyed.

Every existing mechanism against that outcome keys on something that
cannot see it: the re-entry marker is per-`job_id` and the other
execution has a different one (see
[bill-summary-re-entry-guard.md](bill-summary-re-entry-guard.md)); the
supersede gate is per-operator-paste (see
[bill-summary-supersede-gate.md](bill-summary-supersede-gate.md)); and the
locked settles all run after the money is spent. The arm is the only
place the decision is still cheap.

## The decision table

The decision itself lives in `SummaryRunArmDecision`, as one table with a
row per case, and `#arm_row_unless_owned!` only carries it out. Four
consecutive reviews found a defect here, each one a branch the previous
fix did not reach, so the cases now sit together where a reader can see
all eight at once. The rest of this document is the history of why each
row of that table reads the way it does — the table itself is the code.

### Two questions, and it took two attempts to see they were two

**The first is staleness**, and it is not a rule about which statuses may
be armed. `completed` on its own says nothing: an ordinary regenerate
arms a completed row, and that is exactly what the operator asked for.
What is distinctive about the race above is that the status MOVED between
the load and the arm, so the copy a transition would be validated against
describes a row that no longer exists. An ordinary regenerate has no such
gap: the row is `completed` when loaded and `completed` when locked, which
means that half is a compare-and-swap on the value `#perform` loaded — nothing
in this job writes the row between that load and the arm, so any change
in the window is another writer's.

**The second is ownership**, which the swap alone is silent about. A job
that loads the row while another execution is already INSIDE its paid
region reads `generating` at load and `generating` under the lock. The
values match, so the swap passes; `can_enqueue?` and
`can_start_generating?` are both false from `generating`, so nothing
transitions and the arm reported success. The job then bought both calls
over a row another run owned and wiped that run's marker on the way — the
same double charge and lost update the swap was written for, through a
window as wide as the paid region itself, about six minutes. Staleness
was the wrong frame: a run needs to know whether it OWNS the row, not
whether the row changed.

## The claim

The arm therefore now claims the row it arms. `SummaryRunMarker.run_claim` writes
`"run:<job_id>"` — a third value on a column (`summary_run_id`) that
already distinguishes a purchase receipt from an operator's paste — and a
`generating` row carrying anything else belongs to somebody else. The
claim is derived from `job_id` rather than random for one reason: a
worker killed mid-run comes back with the SAME `job_id`, and its own claim
is the only thing that lets it back into its own run rather than waiting
out `GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER`.

### The row still needs a way out

This reasoning used to name `RECLAIM_ABANDONED_AFTER` as the compensating
recovery. That constant is not a clock by itself.
`#reclaim_abandoned_run!` runs in exactly one place — inside
`GenerateBillSummaryService#call` — reached only from `/generate_summary`
and `/regenerate_summary`, and every control that posts to those is
disabled while the row is `pending` or `generating`. An empty
`generating` row draws a badge, one sentence, and one permanently
disabled button. Nothing sweeps it on its own.

As a result, a worker killed on the INLINE pipeline path left a claim no later
execution would ever carry: `RunLegislationPipelineJob` builds a fresh
`GenerateBillSummaryJob` per bill, so the re-run has a new `job_id`,
declines, and returns normally — and the pipeline records that bill's
`summarize` stage as SUCCEEDED over a row that produced nothing, which
`resume` then skips forever. Before that fix, the next arriving execution
recovered the row, which is why this was never visible.

`SummaryRunArmDecision#abandoned?` applies the service's own judgement at
the only other place that can reach such a row, under the same write
lock the decision is already being made in.

### A row with no claim at all reads the same as a fresh row

A `generating` row carrying no marker in `summary_run_id` at all —
`nil`, not a stale claim — gives the arm nothing to compare against.
Two different histories produce that shape: a run that predates the claim
mechanism entirely, or a run that died in the narrow window between the
`generating` transition and `#stamp_arm_marker` writing the claim. Either
way, nothing on the row says this execution does not own it, so it is
treated exactly like a brand-new row and proceeds. A row that has sat
untouched for an hour takes the other path instead — the abandoned-run
reclaim, described above and in
[abandoned-run-reclaim.md](abandoned-run-reclaim.md) — because `updated_at`
is what tells those two cases apart, not the presence of a claim.

### What keeps the claim off a live owner

`#stamp_arm_marker` is what keeps the claim off a live owner, and nothing
else. This reasoning used to name `start_generating!` — but neither
transition fires from `generating`, which is the status every reclaimable
row is in, so on every proceeding case that starts there, no
state-machine save happens at all. It also used to say the marker write
covers it, which was true of only one of that write's two skip branches:
a purchase-receipt resume kept the receipt and wrote nothing, so it
carried its pre-crash timestamp through a positions call of up to six
minutes, and an inline `perform_now` reclaimed it mid-call. The rule is
now uniform — every case that proceeds restarts the clock, whatever it
does with the marker — and the longest quiet window inside one
execution is still a single adapter call.

`#claim_row` itself writes with `update_columns`, which does NOT bump
`updated_at` on its own — an explicit clock restart on that same call is
what keeps this uniform. Without it, a row reclaimed after sitting an hour
untouched would carry that same hour-old timestamp through the whole paid
region that follows, and a second execution arriving a second later would
read it as abandoned too, take the claim over the first execution's live
run, and buy the same pair of calls again — reopening the exact double
charge the fix closed.

The stale gate at the top of `#perform` is NOT a second line of defence
here. It reads `enqueued_at`, which is re-stamped on every retry, and an
inline `perform_now` has none at all. Two different clocks.

### Two markers the claim must not overwrite

- An operator paste. `#clear_stale_run_state_unless_superseded!` re-reads
  it under the lock and hands the row to `#stand_down_mid_run`, which
  settles it onto the pasted body — the hand-off `PasteSummaryService`
  deferred. Standing down at the arm instead would leave that hand-off
  undone and strand the row `pending`, which is why the marker is still
  not part of the staleness comparison.
- This enqueue's own purchase receipt. The re-entry gate reads it next,
  and replacing it with a claim would tell a later execution that
  nothing had been bought yet.

### What the arm deliberately does not decline on

A `generating` row carrying an operator paste. This reasoning shipped
stating the safer behaviour while the code did the opposite — the
ownership test was the claim test or the receipt test, and an
`operator_paste:<uuid>` marker satisfies neither, so the row was declined.
The code moved to match the documented behaviour. The table now
tests the paste marker FIRST, ahead of the status and the clock, which
also stops the reclaim log firing for a row that is about to stand down
.

It proceeds so that the pre-call clear
(`#clear_stale_run_state_unless_superseded!`) can complete the hand-off
`PasteSummaryService` deferred. That service declines to settle a row
that is in flight and logs that a queued or running
`GenerateBillSummaryJob` owns the status and will settle it; if the arm
declines instead, nobody keeps that promise. The row would then sit
`generating` under the paste marker until the reclaim frees it — and the
reclaim CLEARS `summary_run_id`, destroying the marker, so the next
trigger pays and overwrites the hand-written body. That is the exact loss
the arm exists to prevent, and the trap the supersede gate's own
documentation describes.

### How the spec drives a paste into the exact window this covers

A paste seeded BEFORE `#perform` runs never reaches the arm at all: the
supersede gate at the top of `#perform` reads the marker off the row it
just loaded and hands the row straight to `#settle_superseded_row`,
never reaching this code path. To exercise the arm's own paste-marker
handling, the spec has to drive the paste into the row in the window the
finding names — after the load, before the arm's own lock — using the
same one-shot stub technique the sibling "abandoned run" context above
uses to inject state mid-method. Seeded any earlier, the example becomes
a no-op that would pass equally well against the unfixed
code, proving nothing.

The one way to reach the arm at all on an already-`generating` row is the
restart case: job A armed and claimed the row, the worker restarted, and
Solid Queue re-dispatched job A with the SAME `job_id`. Its in-memory copy
therefore still reads `run:A`, so the supersede gate's marker check
returns false (this execution owns the row it is looking at) and the run
carries on to the arm — where the spec's mid-flight paste is waiting.

Proceeding cannot cost money here: `#stamp_arm_marker` leaves the paste
marker where it is, and
`#clear_stale_run_state_unless_superseded!` re-reads that marker under
the lock and hands the row to `#stand_down_mid_run` — all of it before
`Llm::Client` is ever built. That is also why two executions arriving at
a paste-marked row may both proceed without breaking the one-paid-run
rule: neither reaches a paid call.

## The terminal-row paste case the table used to fold into the generating one

`PasteSummaryService#settle_pasted_row!` defers ONLY for `pending` and
`generating` rows. On a `completed` (terminal) row it settles the paste
itself, so there is no hand-off left for the arm to complete — the status
never moves off `completed`. The `summary_run_id` marker alone cannot
distinguish that from the `generating` case: before this fix, the arm read
`:paste_hand_off` for a terminal row exactly as it did for a generating
one, proceeded, and walked an already-finished row through
`completed -> pending -> generating` before the pre-call clear stood it
back down again. Both existing paste examples at the time seeded
`generating`, so the terminal variant went untested.

The final state does not discriminate — either way the stand-down lands
the row back on `completed` with the pasted body. What the fix changes is
the COMMITTED state in between, which is where the harm lives: the Bill
Creator polls this surface every 5 seconds, so an admin who just pasted a
summary watches "Generating…" appear over the text they wrote for a run
that buys nothing; and a crash, deploy, or kamal restart landing in that
gap leaves the row committed `generating` under an operator-paste marker —
the same stranded-row trap that ends with the service-side reclaim clearing the
marker and the next trigger paying to overwrite the paste.

### Timing the paste into the window this covers

The spec for this case seeds the pre-paste `completed` row first, then
lands the paste on the FIRST marker read the run performs — the supersede
gate at the top of `#perform` — by wrapping `SummaryRunMarker.operator_paste?`
so the paste writes on that call's first invocation. The supersede gate
therefore answers off the pre-paste value and the run carries on to the
arm, which is the window the finding names. The row's `generation_status`
is left at `completed` on purpose through this setup: that is exactly what
`PasteSummaryService` does to an already-terminal row, and reproducing
anything else would not be testing this case.

## Decline logging, the row-gone case, and the pre-call clear

The `decision` field on the decline log already names the row of
`SummaryRunArmDecision`'s table; `#decline_message` says what that row
MEANS, because an on-call reader reads the message first. It used to be
one sentence covering the only two declining cases, and "is already
generating for another one" is not what happened when an operator's paste
settled the row before this run reached it.

`decision_name` is carried out of the lock for the decline log only, so
an on-call reader sees WHICH row of the table sent this execution home.

An abandoned run means a worker died. The click or the pipeline run that
surfaced it carries on, so `#log_reclaimed_abandoned_run`'s log line is
the only durable record that it happened — the same reason
`GenerateBillSummaryService#reclaim_abandoned_run!` logs rather than
absorbing it silently.

A row deleted between the load and the arm (`armed.nil?`) means "carry on"
here would mean carrying on into two paid calls whose answers have
nowhere to land, so `#arm_row_unless_owned!` stops rather than buying two
answers with nowhere to put them.

### The pre-call clear: clear_stale_run_state_unless_superseded!

This is the pre-call clear, and the handler for a paste that lands after
the arm. It no longer clears `summary_run_id`, and that is the point
rather than an omission: the arm writes THIS execution's claim onto that
column, and the claim has to stand for the whole paid region or a job
arriving mid-call finds a row that is `generating` for nobody and reads
that as free. Nilling it here would erase the claim microseconds
after the arm wrote it. What it still does is clear the previous attempt's
`generation_error`, and — the reason it re-reads under the lock at all —
stand down when an operator pasted a summary in the window between the
supersede gate at the top of `#perform` and this line.

The clear itself is a WRITE TO THE MARKER COLUMN from inside the run, so
it follows the same rule as the persist sites: re-read the marker under
the row lock first. The supersede gate at the top of `#perform` is only
one statement away, but a paste landing in that gap would be wiped here
otherwise, and the persist-site re-checks downstream would then see
nothing to protect. The rule is uniform on purpose: nothing inside the
paid region writes `summary_run_id` or the summary body without
re-reading the marker under the lock.

The clear is skipped entirely when this execution is here only to finish
the positions half (`resume_positions_only`). The marker is then this
enqueue's own receipt for a summary that is already committed, and
clearing it would hand a later execution permission to buy that summary a
second time. The paste protection does not go with it: every persist site
still re-reads the marker under the row lock before it writes.

A row deleted in this window (rather than in the arm) used to read as
"carry on," on the strength of "the caller hits the same rescue" — but the
rescue it hits is the outer ladder, which sits AFTER both adapter calls,
so a bill destroyed between the load and this line was paid for twice at
full price, with no row for either answer to land on. Stopping here is the
only place that is still free.

`recompute_score: false` on the stand-down here, because this line sits
ABOVE `Llm::Client.build`, so a run standing down here made neither paid
call and moved none of the score's inputs.

The stand-down made this the ORDINARY route for a paste that lands after the
supersede gate — before it, the arm declined and `#perform` returned
before the stand-down existed, so the same underlying condition (a paste
landing mid-run) took two different `recompute_score` decisions depending
only on which side of the gate it landed on. A spurious enqueue here is
not merely a wasted write:
[`RecomputeBillInterestingScoreJob`](recompute-bill-interesting-score-job-design.md)
coalesces per bill with `on_conflict: :discard`, so a genuine trigger — a
`LegislatorVote` upsert, an `OrganizationBillPosition` write — committing
while a spurious enqueue holds the concurrency lock is DROPPED, and the
bill carries a stale score until the daily sweep.

## See also

- [../reference/bill-summary-job-return-values.md](../reference/bill-summary-job-return-values.md)
- [abandoned-run-reclaim.md](abandoned-run-reclaim.md) — the general
  `BillLlmProvisioning#reclaimable?` judgement this arm's abandoned-run
  case relies on.
