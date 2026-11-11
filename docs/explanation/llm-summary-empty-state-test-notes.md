---
mode: explanation
summary: "Test-design notes for LlmSummaryEmptyState.test.tsx: why the fake router/page shapes are load-bearing, and the wording/behavior bugs each example pins (prepare-prompt cost, pipeline-failure alert gating, stale-prompt refusal, paste fallback)."
status: agent-extracted
related: [docs/explanation/bill-creator-empty-state-prompt-flow.md, docs/explanation/pipeline-run-id-cross-tab-coordination.md]
---
<!-- vale Vale.Spelling = NO -->

# Test-design notes for LlmSummaryEmptyState.test.tsx

## Why this file pins the no-draft_org_positions wording

The Prepare-prompt dialog used to ask for `draft_org_positions` in the
reply, though its prompt carries no testimony — inviting positions later
approved as public `OrganizationBillPosition` rows.

The server-side check on the paste endpoint is a separate fix. This file
pins the wording, so the interface stops telling people to go around the
rule.

## Fake router/page shapes are load-bearing

The page argument is not decoration: `PasteSummaryDialog` reads
`page.props` on its first line to tell success from a flash-error
redirect. Omitting it throws the moment a paste is submitted.

The `bill` key matters too: preparing the prompt reloads `summary_prompt`
and `bill` together, and the component reads pipeline status off `bill` —
a fake without it isn't the real response shape.

Load-bearing for `PasteSummaryDialog`'s `landedOnBillCreator` check
: a fake with no `url` makes that check throw instead of catching a
lapsed admin session's real redirect.

## Why summary_prompt is asserted as a fresh top-level prop

The prompt is a top-level prop the server fills only when named — not
returned by this call. That's the point: a prop the five-second refresh
doesn't name cannot be taken away.

## Component scope notes

This component no longer reads the page itself, but the paste dialog it
renders does — on its first line, to tell a clean success from a redirect
carrying flash errors.

The failure alert links to the failed run with `?run_id=`. A plain anchor
is enough here: the assertion is on the href, which is the whole fix.

## The pipeline-failure alert

The alert had never rendered: it was gated on
`billPipelineStatus === "failed"`, but that prop holds only ACTIVE runs —
"failed" can never arrive there.

A GUARD: the alert used to say "check the Solid Queue job logs", but no
jobs dashboard is mounted — that meant an SSH session on the Pi. Nothing
pinned the fix until now.

A wrong old comment claimed the failing run is always what the Pipeline
tab draws next. Sourcing picks that run with no reference to this bill — a
same-tab revisit can show a DIFFERENT bill's run.

The link is what makes the claim true, so this is the example that pins
it. `?run_id=` goes through `find_by(id:)` with no cap, unlike the run
selector's twenty-run list. See
[pipeline-run-id-cross-tab-coordination.md](pipeline-run-id-cross-tab-coordination.md).

The old gate keyed off a busy status. A run that is merely running is not
a failure and must not draw this.

## `handlePreparePrompt`: a reload, not a POST

Building the prompt writes nothing, so the button asks for a prop instead
of posting. It used to POST to `/bills/:id/prepare_prompt`, re-rendering
the whole page for one string.

The prompt arrives as a PROP after the reload lands; this component keeps
no local copy. It used to seed local state once on first render, so a
later-arriving value was ignored.

What the reload does: the prop turns up filled in.

## Prompt staleness

A prompt that survives the pipeline's refresh is the opposite risk: it can
describe the bill's OLD text while still looking current and copyable.

Pipeline status is refetched on the same 5s schedule, so a status change
is the staleness signal — these tests re-render with a different status to
simulate a broadcast or poll.

Refusing is the point. A stale prompt copies cleanly and reads correctly
while describing a bill version that no longer exists.

The remedy has to sit beside the refusal, or the notice is a dead end the
operator can only escape by closing the dialog.

The other side of the wire: an unchanged pipeline must NOT nag.

## `handleCopyPrompt`: never fail in silence

Copy used to return early with no prompt and say nothing at all, while
every other failure path in this file raises a toast. A button that does
nothing reads as a broken clipboard.

## Why the prepared prompt asks for no positions

The prompt comes from `BillSummaryPromptBuilder`: bill details plus its
diff or extracted text, with no hearing testimony — asking for positions
from it is asking the agent to invent them.

## The dialog's schema-key wording bug

The dialog used to name the DB COLUMNS (`llm_summary`, `llm_full_breakdown`),
not the schema's accepted keys — a paste following that wording exactly
was rejected by `config/schemas/bill_summary.json`.

## LlmSummaryPasteFallback

Written before `LlmSummaryPasteFallback` existed here. Unfixed, it would
send an operator holding valid JSON through a paid Generate call just to
unlock a button already on screen.

Checks the specific paragraph, not the whole dialog: the dialog's title
and other text stay truthy even if THIS paragraph is emptied out, so a
whole-dialog check would miss it.

## Generate button busy wording

Generate greys out for both queued and running (`isPipelineBusy`), but the
"Refreshing…" badge explaining why used to show only for running — queued
left a dead button unexplained.

A disabled button is unreachable by Tab, so unless it points at the notice
via `aria-describedby`, the explanation only reaches sighted users. The
Approve button had the same fault.

## Why this screen needed a paste fallback

This screen used to hand out a prompt with nowhere to paste the reply —
not broken, just a dead end; the only path was to generate first, then
paste from the completed or failed view.

## Regression: onSuccess called with no argument

Nothing had tested submitting from here: the fake `router.post` used to
call `onSuccess` with no argument, and `PasteSummaryDialog` reads
`page.props` immediately, crashing the first test to exercise it.

## The full round trip this screen promises

The round trip the Prepare-prompt dialog now promises: prompt out, agent's
JSON in, no generation, nothing paid to the LLM.
