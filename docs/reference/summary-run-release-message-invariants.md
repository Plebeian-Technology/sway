---
mode: reference
summary: "Catalogs what each clause of SummaryRunRelease's two release messages can and cannot prove about the row and its transaction."
status: agent-extracted
related: [docs/explanation/summary-run-release-message-history.md]
---
<!-- vale Vale.Spelling = NO -->

# What SummaryRunRelease's messages can prove

For the reasoning behind why these messages are worded this way, see
[summary-run-release-message-history.md](../explanation/summary-run-release-message-history.md).

## Preconditions

Both messages are written only through `SummaryRunRelease.call`, when
`rearmed_by_caller` is `false`, on a row `#reclaimable?` already confirmed
(`pending` or `generating`, untouched past the threshold), that carries no
operator-paste marker. A pasted body always arrives with that marker in the
same write, and is diverted to `.hand_off_paste!` instead of reaching
either message.

## Clause by clause

| Clause | Applies to | What proves it |
|---|---|---|
| "never started" / "stopped part-way" | both | The status chosen for the message and the status transitioned below it are two reads of the same in-memory record, six lines apart, with nothing reloading between them. That is what keeps them from disagreeing — not one statement doing both. The guarantee holds only because of that code shape: a concurrent writer touching the row inside the same transaction could still break it. |
| "Nothing wrote to it for over `#{threshold}`" | both | This is exactly what `BillLlmProvisioning#reclaimable?` tests. |
| "nothing was charged" | `pending` to `skipped` only | The state machine has no `generating` to `pending` edge, so a row still `pending` after the threshold never reached `Llm::Client.build`. The one writer that leaves a row `pending` for a long time also clears the paste marker in that same locked write. |
| "anything you typed was saved" | both | The release only writes `generation_error` and the status column. No writer of `supplemental_testimony` is reachable from this code path, so all four shapes `SupplementalTestimonyWrite.attrs` can produce survive it. |
| "Any summary on this bill was already there before this run" | `pending` to `skipped` only | `llm_summary` has exactly two writers: `#persist_unless_superseded!` (only runs while `generating`) and `PasteSummaryService` (writes the body and the paste marker together, and a marked row is diverted before reaching this message). A row that does reach this message therefore has a body that predates the arm. It does not claim the body is "from an earlier run" — a superseded operator paste is a body from no run at all. |
| "it may have saved part of its work" | `generating` to `failed` only | Deliberately hedged: the release only checks `generating?`, not `llm_generated_at` or `summary_run_id`, so it cannot tell whether this run or an earlier one saved the body on the row. The persist step runs before the positions call, the category assignment, and `mark_completed!`, so a stopped run may have completed the persist and nothing after it. The wording holds true either way. |

Both messages are drawn on both the failed and skipped screens
(`LlmSummaryFailedReasonNotice` and `LlmSummarySkippedRunNotice`) — see the
linked explanation doc for why that took two separate fixes.
