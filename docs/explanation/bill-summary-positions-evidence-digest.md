---
mode: explanation
summary: "Explains why the positions call only fires when testimony is present, reads committed state, and fingerprints the evidence it reasons from."
status: agent-extracted
related: []
---

# The positions call's testimony gate and evidence digest

<!-- vale Vale.Spelling = NO -->

The positions call in `GenerateBillSummaryJob#perform` fires ONLY when
`provisioning.testimony_present?` — the exact same predicate the Bill
Creator UI's `has_testimony` reads, so the UI and generation never
disagree. It reuses the SAME adapter and `model_at_call_time` already
resolved for the summary call (no second `AdminSetting` lookup). Without
testimony, the call is not made at all, which keeps cost down and the
outcome predictable.

### What a spec must actually assert to pin "reuses the same model"

The contract is a statement about what the two calls are SENT — the same
model string — not about how many times some lookup method ran. A spec
that instead counts `AdminSetting.singleton` calls is not the same
property in either direction: it fails on a harmless change (memoizing,
or reading a second `AdminSetting` field anywhere in the chain), and it
PASSES on the real breakage (handing the positions call a model string of
its own, or reading one from `ENV` — the count stays the same while the
two calls go to different models). The only spec that actually pins the
contract records the model each call received and asserts those two
values are equal.

## Why the attempted-flag is hoisted into a local

`positions_attempted` is hoisted into a local variable because the
nothing-to-generate settlement logic later in `#perform` needs "was the
positions call ATTEMPTED," not "does the row have testimony NOW" — the
positions rescue's `provisioning.reload` can change the second answer
mid-perform, and an attempted-but-failed positions call is not the same
state as a call that never fired. See
[bill-summary-nothing-to-generate-settlement.md](bill-summary-nothing-to-generate-settlement.md).

## Why the testimony check reads committed state

The check is read from COMMITTED state (inside `#settle_under_lock`),
because the summary call sits between the last reload and this line —
120 seconds per attempt with 2 SDK retries, so up to six minutes on the
Claude path. `FetchHearingsService` runs on its own schedule, and its
`:retract` branch clears both testimony columns in that window, so the
in-memory copy could send this run to buy a positions call whose prompt
carries testimony the row no longer holds.

On the has-summary path, `#persist_unless_superseded!` happens to have
reloaded the row under its own lock a few lines earlier. That is a remote
guarantee living in another method, and it is absent on the
testimony-only path — so the read is made local here instead of relying
on it.

`#settle_under_lock` is used rather than a bare `reload` for a deleted
row: `reload` raises `RecordNotFound` into the outer rescue ladder, while
`#settle_under_lock` logs it and answers `nil`, which `|| false` turns
into "buy nothing" — the right answer for a row that is gone.

## The evidence digest

The same lock that reads `testimony_present?` also takes a fingerprint
(`provisioning.testimony_digest`) of the evidence this run is about to
reason from. The positions persist later declines when the committed
value no longer matches that fingerprint. That comparison is what makes
the persist's guard a question about THIS RUN'S evidence rather than
about the bill in general: the bill-level "is there any testimony" answer
stays true through a partial withdrawal, and evidence goes away one
attachment at a time as well as all at once.

See `BillLlmProvisioning#testimony_digest` for the four writers that reach
that state.

## Why the positions persist also stamps the purchase marker

On a testimony-only bill the positions call is the ONLY paid call of the
run, so if the purchase marker lived solely on the summary `update!` a
retry would pay for these positions again. The marker means "this enqueue
has spent money," not "this enqueue bought a summary" — see
[bill-summary-re-entry-guard.md](bill-summary-re-entry-guard.md).

That is exactly why the positions persist site needs the same supersede
re-check the summary persist has. On a testimony-only bill the summary
persist never runs, so guarding the marker write only at the summary site
would leave the positions site stamping `job_id` over an operator-paste
marker — disarming the protection on the very row it was protecting, so
the next queue drain would pay again and destroy the pasted body.

## generation_error is cleared in the same write that persists positions

`generation_error` is cleared in the SAME write that persists the
positions, not at the settle. On the ordinary path this is a no-op — the
pre-call clear (`#clear_stale_run_state_unless_superseded!`) ran a few
lines above and nothing has written the column since. On a
positions-only resume that clear is deliberately SKIPPED, to keep the
purchase marker, and it was the only thing that removed the previous
attempt's `record_failure` message — so without this clear, a resumed row
completed carrying "unexpected adapter error: …", which breaks the rule
`LlmSummaryPositionsErrorNotice` reads (on a completed row, that column
can only have come from the positions rescue) and told the operator the
drafts below were from an earlier run — above drafts this execution had
just bought. Clearing it here, at the write, rather than at the settle
covers every caller of this write by construction.

## Why evidence_digest guards a WHOLESALE column replacement

The positions persist's write is a WHOLESALE replacement of
`draft_org_positions`, a column that carries evidence-retraction marks:
`FetchHearingsService`'s `:retract` branch stamps `evidence_retracted_at`
on every draft left standing, and `ApproveOrgPositionService` refuses each
one. Replacing the array erases those marks and puts Approve back on
drafts drawn from evidence the system had already withdrawn — so the
persist asks, under the same lock that writes, whether the evidence this
run read is still the evidence on the row.

It used to ask `#testimony_present?` instead, which is a question about
the BILL rather than about this run. Evidence goes away one attachment at
a time as well as all at once, and three of the four writers that stamp
the mark leave a non-blank column behind, so a partial withdrawal passed
that guard and erased the marks it had just written.

This does NOT contradict the rule that a successful call clears the mark. That rule holds because the new conclusions rest on testimony
that exists. When that testimony has moved under the run, they do not, and
the mark stands.

## Discarding a positions purchase whose evidence moved: discard_withdrawn_positions!

The positions purchase this run may not land, because the testimony it
was drawn from moved while the call was in flight. The money is already
spent, so the only question left is the same one
`#persist_unless_superseded!` answers for a paste: may this run overwrite
work another writer committed in the meantime. It may not. The drafts on
the row carry that writer's retraction marks, and those marks are what
stops a public `OrganizationBillPosition` being created from evidence the
system has withdrawn.

The log KEY still says "withdrawn," because a withdrawal is what makes
this dangerous and the key is what an on-call reader greps for. The
message says what actually happened, which is that the evidence is no
longer the evidence this run read.

The reason is written to `generation_error` so the operator can see why no
new positions arrived, and RETURNED so the no-summary settle at the end of
`#perform` can carry it — on a testimony-only bill that settle rewrites
this column, and its message is the whole operator-visible output of the
run.

THE PURCHASE MARKER IS STAMPED HERE, in the same write. This is the one
paid path that discards its own answer, and `#persist_unless_superseded!`
returns `:evidence_withdrawn` BEFORE its `update!`, so the receipt was
never written — the row kept the arm's claim and `#resumed_after_purchase?`
read false on the next execution. On the ordinary path this costs
nothing, because the discard is followed by a settle and the job returns;
it bites when something raises between the two — `settle_no_source_text`'s
writes, or the `RecomputeBillInterestingScoreJob.perform_later` this job
names elsewhere as a realistic `SQLITE_BUSY` site. The retry then armed
with no receipt, took the full path, and bought the positions call a
SECOND time for one operator click.

THE WHOLE WRITE IS GUARDED ON THE PASTE, both columns. This is a second
lock, so a paste can have landed since `#persist_unless_superseded!`
checked, and neither column is this run's to write once a human owns the
row. The guard used to cover `summary_run_id` first and leave
`generation_error`, written in the same statement, outside it — not a
smaller version of the same harm: because `llm_summary` is by then the
pasted body, both no-summary arms in `#perform` fall through and the tail
settles the row `completed` still carrying "positions not saved: …". A
completed row's `generation_error` can only have come from the positions
rescue, so the operator was told their positions call had failed, over a
summary they wrote by hand.

The spec pinning this drives the paste in through the real window: the
discard logs before it takes its own lock, so writing the paste marker
from inside that log call lands it exactly between the two locks — the
gap `#persist_unless_superseded!`'s own check and the discard's guard
leave open — which is what the finding describes.
