---
lat:
  mode: explanation
---

# Why isPipelineBusy inverts the status list

`isPipelineBusy` (`app/frontend/components/admin/creator/llm-summary/pipelineBusy.ts`) is the one place that defines what "this bill's pipeline is busy" means.

`TBillPipelineStatus`, the value it reads, is `bill.bill_pipeline_refresh.status` exactly as it arrives. It can be null, because a bill that has never been refreshed has no row to read a status from.

That one check does two jobs at once: it disables every generate and regenerate button on the LLM summary screen, and it decides whether `LlmSummaryPipelineBusyNotice` renders the explanation those buttons point at with `aria-describedby`. Both jobs have to reach the same answer, or a button switches off while the notice explaining why stays blank — an `aria-describedby` pointing at a missing element reads out nothing rather than raising an error, so that failure is invisible to exactly the operators the reference exists for.

## From three copies to one shared check

The check started out as three separate copies of `status === "queued" || status === "running"`, one per call site.

`LlmSummaryStatusShell`'s own comment on the prop it passed down even promised the flag was worked out once by the parent and never recomputed locally, "so the four CTAs cannot disagree about what 'running' means" — and yet the shell passed the raw status down to the notice, which recomputed exactly that duplicated check. Adding a new status and fixing only the parent's copy would switch the buttons off while the notice kept rendering nothing, leaving four buttons whose `aria-describedby` pointed at an element that was not on the page.

## Listing FINISHED statuses, not busy ones

`isPipelineBusy` lists the terminal (finished) statuses, `TERMINAL_RUN_STATUSES`, and treats everything else as busy — rather than listing the busy statuses and treating everything else as idle.

This inversion is not decorative. The pipeline model has seven per-stage statuses, and a run spends most of its life in one of them. An earlier version that listed only the busy statuses read all seven per-stage statuses as idle, so the busy notice disappeared and all four money-spending generate/regenerate buttons turned back on mid-run, while the server's own guard still reported the summary as `completed`. One click bought a second LLM call, racing the pipeline's own summarize step.

Listing terminal statuses means a status nobody recognises counts as still running: guessing "busy" wrong costs a greyed-out button; guessing "idle" wrong costs money. The status names themselves come from the single shared list in `pipeline-controls/stages.ts` instead of being retyped here, so a status added to the model in the future cannot quietly read as "idle" in this file.

## A type predicate, not a plain boolean

`isPipelineBusy` returns a type predicate (`status is Phase52NonTerminalStatus`) rather than a plain boolean, so callers keep the type narrowing an older inline check gave them.

`isPipelineBusy` returns a type predicate (`status is Phase52NonTerminalStatus`) rather than a plain boolean, so callers keep the type narrowing an older inline check gave them — `BillCreatorPipelineStatusBadge` accepts only the busy statuses.

## LlmSummaryPipelineBusyNotice.test.tsx notes

Earlier tests only checked the notice was present (`toBeInTheDocument`), which passed even when its text repeated or contradicted the status badge beside it. These check `textContent` instead.

The badge said "Refreshing…" for a run that had not started yet, one line to the left of text that said "Queued". Whichever the operator believed, the other one was wrong.

## Call-site notes on isBillPipelineRunning

`LlmSummaryStaleHeader`'s regenerate button was the ONE generate control that ignored the pipeline-busy flag.

`LlmSummaryStaleHeader`'s regenerate button was the ONE generate control that ignored the pipeline-busy flag, so it fired a POST that costs money directly beneath `LlmSummaryPipelineBusyNotice`'s "generation is unavailable" text, racing the pipeline's own summarize step — two paid calls for one bill. It now reads the same prop as the branches below it in `BillCreatorLlmSummaryStatus`, which threads `isBillPipelineRunning` through `shellProps` — used to be the one generate control that ignored this flag, firing a paid POST under the shell's own "unavailable" notice.

## The status field on ILegislationPipelineRun

Every run-level status, both in-flight and finished. The list is kept in one place, as `TPipelineRunStatus` in `./stages`, matching the server's.

## pipeline-controls/stages.ts definitions

The `StageKey` type is every hyphenated pipeline stage key the frontend can send, written out as an exact set of allowed strings.

They travel in URL parameters, form fields and WebSocket messages. The same list exists twice on the Ruby side — the `stage_key` type in sig/models/pipeline/stage_keys.rbs and the `Pipeline::StageKeys::KEY_TO_SYMBOL` module — and spec/integration/stage_deps_sync_spec.rb fails CI if the three drift apart. Type checking rejects an unknown stage string anywhere `StageKey` is used. In `STAGES` and `STAGE_DISPLAY_NAMES`, the `"clean-testimony"` stage is labeled `"Process testimony"` with subtext covering the clean, repair, split, group, classify (speaker + stance), and extract organization entities steps so operators see that the stage performs classification and extraction in addition to text cleanup.

`PHASE_52_STAGE_STATUSES` lists the per-stage states a pipeline run can sit in on the server. The "is it running" check lists every one of them, so a run that has moved past plain `running` and is busy inside a stage still counts as in flight.

`PHASE_52_STAGE_STATUS_LABELS` gives operator-friendly labels for the per-stage run statuses above. Kept next to PHASE_52_STAGE_STATUSES so the two cannot drift: BillCreatorPipelineStatusBadge and RunSelector both read this instead of hand-writing their own copies.

`PHASE_52_NON_TERMINAL_STATUSES` lists every state a run can be in while it is not yet finished: queued, running, and each per-stage state. The server keeps the same list. The Cancel button and the "is a run active" checks read this, so a run in the middle of a stage still counts as cancellable. Listing queued and running separately from the per-stage states is what made the old cancellable check, and the query that clears out stuck runs, both miss runs sitting inside a stage.

`TERMINAL_RUN_STATUSES` is the statuses that describe a whole run rather than one stage, kept in this one place so the screens that branch on them (RunConflictBanner, PipelineProgress, BillCreatorPipelineControls, types.ts) stop writing their own copies and drifting apart. It matches the server: a run is finished when it is completed, succeeded, partial, failed or cancelled, and still in flight when it is queued, running, or inside any per-stage state.
