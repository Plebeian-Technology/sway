---
mode: explanation
summary: "Explains why every button that starts a bill-summary run draws through one SummaryRunButton component, sharing one busy label and one screen-reader rule."
status: agent-extracted
related: [docs/explanation/queued-run-notice-copy.md, docs/explanation/llm-summary-notice-phrase-pairing.md]
---
<!-- vale Vale.Spelling = NO -->

# Why every summary-run button is one component

What every summary button says between the click and the reply.

"Queueing", not "Generating", because queueing is what the request does. The
server writes the row and hands the work to a background worker, and only
that worker generates anything. A button that said "Generating…" claimed
something that had not started yet, and the screen then said "Queued…" one
line below it.

## WHY IT IS ONE COMPONENT

There were five of these, hand-written, and they did not agree. "Generate
summary" on the empty state swapped to "Generating…", "Regenerate from
latest data" in the out-of-date header swapped to "Queueing…", and
"Regenerate summary" on the completed view swapped to nothing at all — it
only went grey. Grey is what this screen also shows when a pipeline run is
BLOCKING generation, so the one control that most needed to say "your click
worked" said "you cannot do this" instead.

The busy word and the screen-reader rule live here rather than at each call
site, so a sixth button cannot drift away from the other five. Each site
keeps only what is genuinely its own: its words, and its own reasons for
being shut.

## Field-level notes

`busy`: THIS button's own request is in flight. Swaps the label and shuts
the button.

`LlmSummaryCompletedActions`'s `runLoading` prop feeds this: THIS screen's
own start-a-run request, not the server's queued/running status — else
another tab's run would make this button falsely claim the operator just
clicked it.

`LlmSummaryCompletedView`'s `runLoading` prop: THIS screen's own
start-a-run request — Regenerate's words read it, not `isRegenerating`,
which also folds in a queued/running status from elsewhere.

`disabled`: Every OTHER reason this button is shut. `busy` is deliberately
not folded in by the caller: this component ORs it in itself, so a button
that says "Queueing…" can never also be clickable.

`pipelineBlocked`: A legislation pipeline run is blocking generation. Kept
apart from `disabled` because it decides what a screen reader is TOLD, not
what is allowed: a button greyed out because a run of its own is going must
not blame the pipeline, and in that case the notice it would point at is
not on the page.

## Call-site echoes

`LlmSummaryCompletedActions`'s "Regenerate summary" button used to only go
grey when clicked — indistinguishable from the pipeline-blocked disabled
state. It now draws through the shared button, with the same busy word its
three siblings use.

The abandoned-run exit in `BillCreatorLlmSummaryStatus` uses the same label
as `LlmSummaryGenerateBranch`'s button for this exit — both post to the same
endpoint. Both draw through `SummaryRunButton`, so the busy word can't
drift.

The disabled `Button` shown for a non-abandoned empty `generating` row is a
plain `Button`, not `SummaryRunButton`: this one has no handler and can't be
pressed, so it must not claim a busy word like "Queueing…".
