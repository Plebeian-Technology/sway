---
lat:
  mode: explanation
---

# Why SummaryRunRelease writes two different messages

What the operator reads on a row `SummaryRunRelease` released is short, plain, and names the only next step there is: the worker that was going to finish the run died without logging anything.

## One message could not be true of both arms

The original wording was a single sentence: "No summary was made and nothing was charged." The two arms of `.call` do not stand in the same place, so the same claim could not hold for both:

- **`pending` to `skipped`**: the row never reached
  `#arm_row_unless_owned!`, and the state machine has no `generating` to
  `pending` edge, so a row still `pending` after the threshold genuinely
  never reached `Llm::Client.build`. Both halves of the original claim hold
  here.
- **`generating` to `failed`**: the row is `generating` only after the arm,
  and the arm runs the statement right before the adapter is built —
  everything a run spends, it spends while `generating`. A worker killed
  during the positions call leaves a row holding a paid-for `llm_summary`,
  and `BillCreatorLlmSummaryStatus` routes any row with content to the
  completed view, so "nothing was charged" printed directly above the
  summary that had, in fact, been made and charged for — inviting the
  operator to pay for it again. This arm now makes no claim about cost
  either way.

This is the same fix `GenerateBillSummaryJob`'s positions rescue already made, where a similar claim was made conditional on a summary already being on the row.

## The rule both sentences follow

Every clause has to be true of every state that reaches it.

Where the release cannot tell two states apart, the clause is hedged or dropped — never guessed. Fixing the cost claim left a second clause on each arm that the release could not actually see far enough to make:

- The `pending` arm said "anything on this bill is from before it." But the
  click that arms the row also writes `supplemental_testimony`, and on a
  replacing paste stamps `evidence_retracted_at` on every draft — in the
  same lock, one statement before `enqueue!`
  (`GenerateBillSummaryService#call`). Both effects land at the same moment
  the run is released. Worse, `GenerateBillSummaryService::UNQUEUED_ERROR`
  can land on a row armed by that same click and says "anything you typed
  was saved" — so one click could produce two messages that contradicted
  each other. The `pending` arm now says the same thing, word for word.
 
- The `generating` arm said "anything on this bill is what it saved before
  it stopped." But the release only reads `generating?`, not
  `llm_generated_at` or `summary_run_id`, so it cannot know whether this
  run is what saved the body standing on the row. A run killed before its
  first `#persist_unless_superseded!` call saved nothing, and the body
  belongs to the run before it — credited on a screen whose whole purpose
  is provenance. The sentence is hedged instead, to what the ordering can
  prove: the persist step runs before the positions call, the category
  assignment, and `mark_completed!`, so a stopped run *may* have saved part
  of its work.

## Both arms need to reach a screen

For a while only one did.

`generating` to `failed` is drawn by `LlmSummaryFailedReasonNotice`. `pending` to `skipped` was drawn by `LlmSummaryGenerateBranch`, which `BillCreatorLlmSummaryStatus` only reaches when the row carries nothing at all. But a released regeneration keeps the previous run's summary, so it went to the completed view instead — where every consumer of `generation_error` returns null for a `skipped` row. That is the ordinary way to reach a stuck row, so the message written for exactly this operator was filtered out on exactly their route. `LlmSummarySkippedRunNotice` now draws it on both views.

## The threshold is interpolated, not spelled out by hand

It used to read "for over an hour" — a hand-copy of `GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER`.

Change that constant to thirty minutes and the sentence an operator reads goes false, while `bin/rubocop`, `bin/steep check`, and the whole test suite stay green. Since the value is derivable, it is derived (`1.hour.inspect` reads as `"1 hour"`). A comment must never state a fact nothing enforces, and that rule applies with more force to a user-facing string, not less.

## Neither message names a button

Both used to end by telling the operator to press "Start a new run." The screens that draw them.

Both used to end by telling the operator to press "Start a new run." The screens that draw them, `LlmSummarySkippedRunNotice` and `LlmSummaryFailedReasonNotice`, usually sit under the completed view, where the control reads "Regenerate summary." The one button that ever said "Start a new run" has since been renamed to "Generate summary," so the exact words these messages quoted exist nowhere in the app. A message that quotes a label goes stale the moment somebody renames the button, and nothing fails when it does — so the messages describe the action instead.
