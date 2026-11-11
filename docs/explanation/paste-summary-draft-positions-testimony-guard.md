---
mode: explanation
summary: "Explains why PasteSummaryService only lets a paste add draft org positions when the bill has testimony, and why it ignores rather than rejects a violation."
status: agent-extracted
related: ["docs/explanation/paste-summary-draft-positions-lock-merge.md"]
---
# The testimony guard on pasted draft org positions

<!-- vale Vale.Spelling = NO -->

`PasteSummaryService#draft_positions_attrs` decides whether a pasted
summary is allowed to change the bill's `draft_org_positions`.

## Presence of the key decides whether the column is touched

`draft_org_positions` is optional in a pasted payload, because the
summary call itself no longer produces it. The stored column is only
overwritten when the pasted JSON actually contains the
`"draft_org_positions"` key — the key's presence is what matters, not
whether its value is empty. An operator who pastes an empty list clears
the existing drafts; an operator who leaves the key out entirely leaves
the stored drafts untouched.

## Why a non-empty list requires testimony

Only two places in the codebase can **add** an entry to this column:
`GenerateBillSummaryJob`'s positions call, and this line. The job already
checks `provisioning.testimony_present?` before adding anything — the
same question the Bill Creator asks for its `has_testimony` flag. This
line, at one point, did not check it, which made a paste an unguarded way
to add org positions around the rule the job enforces.

That rule exists because approving a draft creates a public
`OrganizationBillPosition` — a claim, visible to everyone, that a named
organization supports or opposes a bill. If that claim was built from the
bill's text alone rather than from real testimony, the system is putting
words in an organization's mouth. Guarding the generated path but leaving
the pasted path open was the classic "fixed one of the two places"
mistake.

Two other places touch this column —
`BillDraftOrgPositionsController#apply_draft_decision` and
`ApproveOrgPositionService#delete_approved_draft` — but they only ever
change or remove an entry that is already there. They can't add one, so
they are deliberately left unguarded.

## Why an empty list is always accepted, testimony or not

An empty `draft_org_positions` list makes no claim about any
organization, so it carries none of the risk the guard exists for. It is
also the operator's only way to retire drafts that an older, unguarded
run built from bill text alone. A guard that blocked the clear would
block the cleanup along with the abuse it's meant to stop.

## Why a blocked non-empty list is ignored, not rejected

If a bill has no testimony and the paste includes a non-empty
`draft_org_positions` list, the positions are dropped and logged
(`paste_summary.positions_ignored_no_testimony`) — but the rest of the
paste still succeeds. The summary text in the same paste is real,
separate work, and `PasteSummaryService#call`'s return contract has no
"partly accepted" outcome. Rejecting the whole paste over the positions
would throw away the summary along with them. Leaving the log line
instead of staying silent means the drop is still visible to whoever
reads the pipeline log, and the stored positions are left exactly as they
were, so nothing an earlier operator already sorted through is lost
either.

## Preserving marks across the replace

The write below replaces the whole `draft_org_positions` column, which
would otherwise silently drop the internal marks
(`BillLlmProvisioning::INTERNAL_DRAFT_MARKS`) already sitting on the
stored entries — a pasted JSON payload was never going to carry those
keys, since each one records an internal fact that a later paste has no
business clearing. `BillLlmProvisioning.draft_org_positions_preserving_marks`
carries each mark forward onto the pasted entry it still describes,
matching by content rather than position (see
[paste-summary-draft-positions-lock-merge.md](paste-summary-draft-positions-lock-merge.md)
for why that matching has to happen inside the write lock, and
[draft-org-position-identity.md](draft-org-position-identity.md) for why
matching by content is the right rule).
