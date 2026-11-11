---
lat:
  mode: explanation
---

# Test-design notes for BillCreatorLlmSummaryStatus.test.tsx

Explains BillCreatorLlmSummaryStatus.test.tsx's own test-design rationale — why each example is not redundant with its neighbor, and the mount-point/wording bugs each one guards against.

## Why this file exists as a second mount point

`LlmSummaryCompletedView.test.tsx` pinned the wiring on the COMPLETED branch — a guard audit found changing one token there stayed green under every gate. It closed one of two mount points.

This file is the other mount point: `BillCreatorLlmSummaryStatus` hands the same fields to the NOT-YET-SUMMARIZED branch. Nulling the attachments hand-off there stayed green under vitest and tsc.

Same failure shape: these deliverables fail SILENT — rendering nothing looks like the healthy case, so a leaf test cannot catch a mis-wire. The subject is only whether this hands each field along.

## Why the ordinary-generating example is not redundant with the pending one

The example above is why the one below is not redundant — they differ in `generation_status` alone, so the wording must come from that column and nothing else.

The pending-only hedge missed the LIVE generating arm too — `GenerateBillSummaryJob` persists `llm_summary` WHILE generating, so a generating row's draft may be that run's own work.

The row here is ORDINARY — a live run writing, with the previous draft still on screen. Nothing was stuck, so it is not reclaimable.

On `generating`, nothing is provable like `pending`: `llm_summary` persists WHILE generating, so a killed worker leaves its own paid summary — crediting it to "last run" misattributes it. The example that was meant to cover this arm asserted only the verb.

## Why the Approve-notice example reads the notice text, not just the wiring

A disabled button cannot be tabbed to, so the notice above the list is the only place the reason reaches a screen reader.

IT READS THE NOTICE, not just the ids: this used to assert only the `aria-describedby` wiring. The pointed-at notice never mentioned Approve on the ordinary render.

"comes back when sway releases the run" was wrong here: `SummaryRunRelease` is what the reclaim sweep calls on an abandoned row, not what an ordinary finished run does.

## Why the abandoned-row notice examples cover four arms

Browser and server disagreed on the same stuck row — both notices called it "stopped without finishing" on every status, but the sweep settles `pending` with "never started".

The release has the proof: a `pending` row never reached `#arm_row_unless_owned!`, and there's no `generating -> pending` edge, so a row stuck at `generating` did start and may have already paid.

Four arms: two notices, each with two statuses to get right — pinning only the wrong arm would pass a component that swapped the sentences instead of splitting them.

## Why the paste-carrying-row example exists

A paste-carrying row never reaches either server message — `SummaryRunRelease.call` checks the marker first, diverting to `.hand_off_paste!`, finishing the row for free and keeping the text.

By design: `PasteSummaryService` writes the marker with the body in one update, declining to settle a pending/generating row. Pasting onto an in-flight row is a supported, free rescue.

The operator was told "Regenerate" — buying two model calls and overriding their pasted summary. Money spent destroying their own text, shortly before the free sweep would have kept it.

## Why the fixture disagrees the two paste columns on purpose

The fixture where the two paste columns DISAGREE — the pair above and its Ruby twin moved `llm_provider` and the marker together, so neither could catch the branch reading the wrong column.

Ordinary row: operator pastes, then presses Regenerate. The service nils `summary_run_id` but never touches `llm_provider`, so the row queues as "operator_paste" unmarked; the worker dies.

`SummaryRunRelease.call` reads the MARKER, writing `RELEASED_UNSTARTED_ERROR` and marking the row skipped — wording false throughout, talking the operator out of the only control that gets a summary.

## Further scattered test notes

New this round: the reclaim sweep can release a `generating` row to `failed` holding a summary the released run itself bought. The server won't say who saved what, so the notice must not either.

`SummaryRunRelease::RELEASED_IN_FLIGHT_ERROR`, copied by hand because it is a server constant.

It used to read "The summary above is from an earlier run" — both halves false after the summary box moved: the summary is BELOW the notice, and the editor holds `bills.summary`, which no run writes.

Arming a regeneration clears neither `llm_summary` nor `draft_org_positions`, so a `pending`/`generating` row holds the last run's work while queued — a panel drawing neither wipes the screen silently.

The draft notice, for the reason the failed-row example above gives: the editor holds the PUBLISHED summary.

Same mislabeled-paste harm, one component over: Generate never clears `llm_provider`, so an operator's paste can be mislabeled "the model's draft … from the last run."

The drafts really are replaced, so a notice that simply dropped the promise would pass the example above while telling the operator nothing about the cards.

ONE RULE FOR ONE STATE: both branches draw a `pending` row but used to disagree on the supplemental field's readOnly state, decided by whether a summary survived the last run.

Reject and Edit stay live for the reason the card already gives for its other two gates: neither publishes anything, and Reject is the operator's way out of a draft they have judged stale.

An empty `generating` row used to disable its button with no way out — the header can't rescue it either (needs `llm_generated_at`). A sweep now settles it, published as `reclaimable`.

`BillLlmProvisioning#reclaimable?` is `pending? || generating?`, but the panel above checked it only in the empty `generating` branch — every other stuck-row panel still drew a dead control.

This block walks all of them: reclaimable while `pending` or `generating`, with or without content, plus the header. Each pairs with `reclaimable: false` so an undisabled button can't pass.

Empty `pending`: a worker that dies before `mark_generating!` leaves the row here forever, and the generate branch used to hold its button shut on `isPending` alone with no notice and no exit.

It read "Approve stays off until this bill has a run that finished" — but both gates are `pending || generating` only, so the sweep reopens Approve with no run ever finishing.

THE ROUTE MOST STUCK ROWS TAKE: a regeneration armed on a bill with an existing summary goes `pending`; the worker dies, and an hour later the sweep releases it and marks the row `skipped`.

The row still carries content, so it routes to `LlmSummaryCompletedView`, not the generate branch — whose `generation_error` readers return null for `skipped`, leaving the reason unshown.

`SummaryRunRelease::RELEASED_UNSTARTED_ERROR` ends in `skipped`. The old fixture's one message served both arms, claiming nothing was charged — false for the `generating` arm.

It also claimed "anything on this bill is from before it" over `supplemental_testimony` the arming click just wrote. A hand-copied server string; re-copy whenever it moves.

THE SAME SENTENCE ON THE SIBLING NOTICE: `skipped` can follow a `completed` row whose pasted body a later Generate superseded — "draft from an earlier run" would be wrong twice over.

Read off the DRAFT NOTICE, not the editor: the editor holds `bills.summary` (published); `llm_summary` is the model's draft on a different record.

Was "from an earlier run" — unprovable on a `failed` row, since the job commits `llm_summary` BEFORE it can fail. `hasDraft` is `!!llm_summary`: exists, not when written.

Positions get no such branch: `PasteSummaryService` leaves `draft_org_positions` alone when omitted, and persist overwrites `llm_provider` before positions returns — never dated.

"The new run replaces them" was written when the editor held `llm_summary`; it now holds `bills.summary`, which no run writes — an admin's own summary was falsely promised a replacement.

The Regenerate guard covered only one arm: narrowing `runInFlight` to `status === "pending"` let a `generating` row with content offer a second paid run.

Routing a queued row to the completed view stopped at ONE button: the draft cards came too, and Approve — which creates a public org position — was never checked against row status.

The server now refuses it too, with `:run_in_flight`, checked before and under the write lock. This example holds the client half: what a card shows BEFORE a click earns a refusal.

`showConfirmDialog` is never reset when `isRegenerating` (the server's `runInFlight`) flips true then false unprompted — the dialog can close and reopen over a Confirm that buys paid calls.

A `generating` row DID start — that status is entered only after `GenerateBillSummaryService`'s arm — so this is the arm that mirrors `SummaryRunRelease::RELEASED_IN_FLIGHT_ERROR`.

The job gates each call separately — summary needs source text, positions needs `has_testimony` — so a restart costs two calls only when both exist.

THE ONE THIS FILE EXISTS FOR: a bill whose summary never generated and whose attachment downloads failed is exactly the case where pasting the text by hand is the only way forward.

The other side of the same wire: an empty mirror must render nothing, so the assertion above cannot pass on a hardcoded value.

A terminal row can still hold real work: the generate branch renders no orgPositions or summary, so routing a row there hides drafts an operator must approve or reject.

A bill with testimony but no bill text lands here on EVERY run: the positions call succeeds, the summary call is skipped for want of source text, and the job settles `failed` with an explanation.

rawIndex is the position in the UNFILTERED server array, which is what the approve/reject endpoints count by.

The second half of this notice, previously untested: when a draft survives the failure, the notice must say so — else the operator reads a red alert with no sign a draft survives.

The other side: with no draft on the row, the claim must not be made. It reads "draft", not the old "from an earlier run" — this would pass on a component making the claim unconditionally.

btn-retry-summary is the distinguishing element: it exists only on the generate branch. The badge is drawn on both, proving nothing about which branch ran.

runInFlight is `pending || generating`, not relaxed for an abandoned row, so the aria pointer is set on both arms — these two examples fail on any edit that moves the sentence back into one arm.

The other direction: a run genuinely in flight must still hold the button shut, or a panel that stopped disabling it would pass the example above while offering a second paid run over a live one.

Switched off by isBillPipelineRunning like every generate/regenerate button, but pointed at nothing — no explanation for a screen reader, and no data-testid for a gate to find it by.

BRANCH 2: a stuck row holding earlier content routes to the completed view, where runInFlight held Regenerate shut — the out-of-date header can't rescue it either (#stale? needs llm_generated_at).

Approve stays shut either way, by design: ApproveOrgPositionService#run_in_flight? refuses on `pending? || generating?` with no reclaimable test — an enabled Approve here would just earn a refusal.

BRANCH 3: the shell's out-of-date header — the ONLY regenerate button on a stale row (LlmSummaryCompletedActions hides its own via `{!stale && …}`), disabled by the same queued-or-running test.

The other side: a `completed` row's generation_error belongs to the positions rescue, already worded by LlmSummaryPositionsErrorNotice — a notice drawn for every status can't pass this.

The verb phrases of RELEASED_UNSTARTED_ERROR/RELEASED_IN_FLIGHT_ERROR are kept as constants so every example reads as "the browser used the server's words", and the pair is edited together.

The Ruby side is pinned in spec/jobs/reclaim_abandoned_summary_runs_job_spec.rb, which fails if either constant drops its phrase — a hand-copied server string otherwise goes stale silently.

A row still carrying earlier work goes to the completed view (LlmSummaryInFlightNotice) — the route the review walked: completed row, Generate clicked, worker never picks it up.
