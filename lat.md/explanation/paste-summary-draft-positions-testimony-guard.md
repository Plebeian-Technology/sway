---
lat:
  mode: explanation
---

# The testimony guard on pasted draft org positions

`PasteSummaryService#draft_positions_attrs` decides whether a pasted summary is allowed to change the bill's `draft_org_positions`.

## Presence of the key decides whether the column is touched

`draft_org_positions` is optional in a pasted payload, because the summary call itself no longer produces it.

The stored column is only overwritten when the pasted JSON actually contains the `"draft_org_positions"` key — the key's presence is what matters, not whether its value is empty. An operator who pastes an empty list clears the existing drafts; an operator who leaves the key out entirely leaves the stored drafts untouched.

## Why a non-empty list requires testimony

Admitting an organization position into draft positions requires factual evidence from committee hearing testimony or verified local news reporting.

The persistence guard checks `provisioning.testimony_present?` and validates candidate positions against source snapshots through `NewsOrgPositionGroundingService.filter_draft_positions`. Without testimony or grounded news articles, positions derived from raw bill text could invent claims on behalf of organizations. Filtering both generated and pasted paths guarantees that positions cannot bypass factual evidence verification.

## News reporting as an alternate factual basis

Approved local news reporting articles provide an alternate factual basis for draft organization positions when hearing testimony is absent.

When a bill lacks committee hearing testimony but has approved local news reporting, candidate draft positions are admitted only if they contain verbatim direct quotations from authorized institutional spokespersons or official statements. Positions lacking direct quotes, attributing statements to rank-and-file members, or referencing public bodies are dropped before persistence.

## Why an empty list is always accepted, testimony or not

An empty `draft_org_positions` list makes no claim about any organization, so it carries none of the risk the guard exists for.

It is also the operator's only way to retire drafts that an older, unguarded run built from bill text alone. A guard that blocked the clear would block the cleanup along with the abuse it's meant to stop.

## Why a blocked non-empty list is ignored, not rejected

If candidate positions fail grounding and the bill lacks testimony, ungrounded positions are dropped and logged while accepting the summary body.

The summary text in the same paste is real, separate work, and `PasteSummaryService#call`'s return contract has no partly accepted outcome. Rejecting the whole paste over the positions would throw away the summary along with them. Leaving the log line instead of staying silent means the drop is visible in the pipeline log, while preserving existing curated drafts without loss.

## Preserving marks across the replace

Replacing the `draft_org_positions` column preserves internal triage marks previously stamped on existing entries.

A pasted JSON payload does not carry internal operational marks. `BillLlmProvisioning.draft_org_positions_preserving_marks` carries each mark forward onto matching entries within the row write lock, preventing accidental erasure of review status or retraction timestamps.
