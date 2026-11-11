---
mode: explanation
summary: "Why BillCreatorLlmSummary reads bill without optional chaining, keeps summary_prompt as a top-level prop, and how its generate/save/clear supplemental-testimony handlers report failure to the operator."
status: agent-extracted
related: [docs/explanation/bill-creator-landed-write-detection.md, docs/explanation/supplemental-testimony-clear-endpoint-rationale.md, docs/explanation/org-position-bill-testimony-check.md, docs/explanation/supplemental-testimony-write-rule.md]
---
<!-- vale Vale.Spelling = NO -->

# BillCreatorLlmSummary mechanics

## Why summary_prompt is a top-level prop, not nested in bill

A TOP-LEVEL prop, not nested in `bill`: Inertia's partial reload merges
only one level deep, and this tab polls `bill` every 5s, so nesting here
would wipe it on each refresh. Nesting used to empty the prompt dialog on
its own.

## Why the server's state is the only source of truth

The server's state is the source of truth — nothing here shows as done
before the server confirms it, including while a regeneration is in
flight.

## Why `bill` is read with plain access, not `?.`

`bill` is always present here: IPageProps guarantees it, and the only
caller, BillCreatorSummaryAndPositions, renders this only once
bill?.id > 0.

So reads on `bill` use plain access, not `?.` — a chain that can never fire
reads as proof the value can be missing, which is worse than no check.

## Why orgPositions filters rejected drafts and records rawIndex before filtering

Comes straight off the provisioning prop; the paste dialog's redirect (an
Inertia GET back to this tab) redraws the cards on its own, with no
router.reload here.

`rejected: true` entries are filtered out as a precaution — the server now
deletes a rejected position outright, so this should never actually find
one.

rawIndex is recorded BEFORE the filter — the server indexes into the
unfiltered draft_org_positions list.

So a post-filter position would point at the wrong entry once an earlier
one is rejected: approving the visible second card could delete the first.

## Why handleGenerate and handleRegenerate are two different code paths

Backs both buttons on LlmSummaryGenerateBranch — "Generate summary" and
"Retry" — which POST to /generate_summary and write no audit entry.

The regenerate-confirm and out-of-date-header buttons go through
handleRegenerate to /regenerate_summary instead, which does write one
(summary_regenerate).

## Why handleGenerate needs its own onError and a two-part onSuccess

BillsController#generate_summary refuses via `inertia: {errors: {generation:
message}}`, not flash[:alert] — and registerFlashToasts only reads flash.
Without this handler, a refusal showed nothing.

This button costs two model calls, so a generic banner isn't enough — the
operator needs to know generation specifically wasn't queued. See
[bill-creator-landed-write-detection.md](bill-creator-landed-write-detection.md)
for why the handler checks `pageExpired` before `landedOnBillCreator`.

This button costs two model calls, so a silent bounce is worth flagging.
Same seam as the summary and supplemental saves below.

## Why handleRegenerate is shared with the empty-state branch

Shared with the empty-state branch via useRegenerateSummary; carries the
pasted testimony along, same as handleGenerate — the only regenerate
button for an out-of-date summary.

## Why handleSaveSupplemental has its own confirm, and how replacesStoredTestimony is computed

Saves testimony alone, no model call — before now only Generate/Regenerate
sent it.

The discriminator below must match the server's own retraction rule — see
[supplemental-testimony-write-rule.md](supplemental-testimony-write-rule.md).

No "reload" in the message: it already happened. Inertia follows the
rescue's redirect with a GET, and inertia_rails issues a fresh XSRF-TOKEN
cookie on that response, so the next click works. See pageExpired.ts.

## Why the Clear button (handleClearSupplemental) is built the way it is

No local setSupplementalText: the server redirects back, Inertia follows
with a GET, and the re-seed logic above picks up the new empty value — the
field clears because the SERVER cleared it.

preserveScroll: every sync reload here needs it, and this button sits
below a 16-row text box — without it, the redirect drops the operator back
at the top of the page.

onError matters here: this is one of three places writing `has_testimony`,
which gates Approve on every draft card.

If the PATCH fails, there's no re-seed, so the text box still shows text
the operator believes cleared — failure would look exactly like success.

No notifyServerRefusal: BillsController#supplemental_testimony has no
refusal-key path to read — it calls the service and redirects regardless —
so this is the only honest message available.

Says "on this bill", not "below": Clear also appears on the generate
branch, reached while a prior run's drafts are stored but not rendered —
"below" would count positions the operator can't see.

Clear's onSuccess uses the same seam as the save above, including the
page-expired redirect that seam missed and the reload nobody has to make.

## `IOrgPosition.rejected`

Set on entries left over from before a rejected position was deleted
outright. `BillCreatorLlmSummary` filters them out as a precaution.

Declared here rather than cast in at the one place that reads it: the
server can send it, so the type that describes what the server sends
should say so.

## Why LlmSummaryOrgPositions's card key must not shift on approve/reject

`index` is the server's handle on a draft (its RAW array slot), not this
list's position. The KEY must NOT shift on a neighbour's approve/reject —
using `rawIndex` as key used to lose unsaved edits.

## Why there is no handleRemoveOrgPosition

No handleRemoveOrgPosition: Approve/Reject redirect to
summary_bill_creator_path, and Inertia's GET already redraws the page with
a fresh `bill` prop — a manual reload here would be redundant.

## Why publishedSummary reads bill.summary, not provisioning.llm_summary

bills.summary is the column the public page reads and Save summary writes.
The box used to seed from provisioning.llm_summary instead, silently
publishing the model's draft over it on every save.

## What LlmSummaryCompletedActions is

The row of buttons under a finished summary: regenerate, which queues an LLM
job, and paste summary JSON, where the operator supplies the text themselves
and no LLM is involved.
