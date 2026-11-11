---
lat:
  mode: explanation
---

# Why LlmSummaryEmptyState's prompt flow works the way it does

Checks only whether a provisioning record exists — bills that amend nothing (resolutions, appointments) have empty `diff_content` even when their `llm_summary` is perfectly good.

## billId is always present

Always present: the only caller reads `bill.id` plainly and its own caller gates on `bill?.id && bill.id > 0` before rendering this tab, so `| undefined` here would draw an unreachable branch.

## IPreparedPromptPage is named, not asserted inline

Named rather than asserted inline: an inline `as` is a claim about a shape nobody can find again, and this shape is already in this component's test.

## Capturing the pipeline status a prompt was built against

Captures the pipeline status when the prompt was built, since the prompt survives a refresh — a stale prompt could stay on screen and copyable with no warning otherwise. Captured, not a ref.

## handlePreparePrompt: a reload, not a post

Writes nothing, so this asks for a prop via reload, not a post. `bill` is asked for alongside it so the pipeline status comes from the SAME server render as the prompt, not the last 5s refresh.

No `preserveScroll` here, unlike other requests on this screen: `router.reload` always sets it itself and its options type leaves it out, so passing one is a compile error, not a redundancy.

## handleCopyPrompt: refusing to copy is the point

Never fail in silence. A button that does nothing reads as a broken clipboard, and the operator retries it instead of preparing again.

Refusing to copy is the point. A stale prompt is worse than no prompt: it copies cleanly, reads correctly, and describes a version of the bill that no longer exists.

## The prompt survives the 5s refresh on purpose

The prompt survives the 5s refresh, so it can describe a bill version the pipeline already replaced while still copying cleanly. Said, not silently repaired.

## The Prepare-again button sits beside the refusal

The remedy sits beside the refusal. Without it the operator has to close the dialog to find the Prepare prompt button again, and the notice reads as a dead end.

## Generate button copy

Posts to `/regenerate_summary`; with no source text at all it answers `:no_pipeline_data` — hence the "No pipeline data available" message above it.

Used to say "Generating…" while only queued. Now says "Queueing…", the same word every start-a-run button on this screen uses.

## LlmSummaryPasteFallback

Without this, the screen asked for JSON with nowhere to put it. Dialog wording names the keys the schema accepts, so following it doesn't lead to a rejected paste.

Used to say to run Generate first — false once `LlmSummaryPasteFallback` appeared above, and following that advice paid for two model calls to reproduce text the operator already held.

## LlmSummaryPipelineBusyNotice reads the same statuses as the button

Reads the same statuses that grey out Generate above, so the button and its explanation can never disagree — it used to appear for "running" alone.

## The pipeline-failure alert

`billPipelineFailure` is the bill's most recent failed run, whole, or null.

ONE PROP: message and run id come from one row. Links here since Resume/Restart belong to whichever run the Pipeline tab shows. See [[docs/explanation/pipeline-run-id-cross-tab-coordination.md|pipeline-run-id-cross-tab-coordination.md]] for the backend side of why the run id travels with the message.

Gated on the ERROR now, not a status: `billPipelineStatus === "failed"` can never arrive, since that prop holds only ACTIVE runs — the alert never rendered before this.

`TBill.bill_pipeline_last_failure` is the most recent run that FAILED, which `bill_pipeline_refresh` can never carry: it holds only ACTIVE runs, and `failed` is deliberately not an active status. Without this the summary tab's "Pipeline failed" alert was gated on a status the prop could not deliver, so it never rendered once — the operator saw "run the legislation pipeline first" about a run that had just failed.

The link carries the failed run's own id: without it, the Pipeline tab shows whichever run it last picked, which could be a DIFFERENT bill's run, hiding Resume/Restart for this one.

`error_message` can be blank (a force-failed or swept run has none), so this says "no reason recorded" — the old guard dropped the whole alert on a blank message instead.

## LlmSummaryPasteFallback itself

The manual paste way out for a branch whose only other button pays for both LLM calls again. Kept as its own component: the repetition is one `useState`, not a shared rule to drift.

Its `size` prop matches the row of buttons it is dropped into. `LlmSummaryEmptyState` puts it in a `size="sm"` row; the failed-branch row uses the default size.

## No draft_org_positions in the prepared prompt

No `draft_org_positions` here: with no testimony, the agent would invent positions that could get approved into PUBLIC records.

Key names are what the schema accepts, not DB columns. See [[docs/explanation/bill-positions-prompt-security.md|bill-positions-prompt-security.md]] for the backend prompt-security rationale this mirrors.
