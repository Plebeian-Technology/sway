---
mode: explanation
summary: "Explains why ApproveOrgPositionService checks bill-level testimony presence in addition to the per-draft evidence-retracted mark, and what recovers from a refusal."
status: agent-extracted
related: ["docs/explanation/evidence-retraction.md", "docs/explanation/positions-run-evidence.md", "docs/explanation/testimony-write-decision.md"]
---

<!-- vale Vale.Spelling = NO -->

# The bill-level testimony check

`ApproveOrgPositionService#bill_testimony_missing?` is true when the caller
named a draft and the bill has no testimony left to have drawn it from. It
reads `BillLlmProvisioning#testimony_present?` — the SAME check that decides
whether the positions LLM call runs (`GenerateBillSummaryJob`'s
`positions_attempted`), whether `PasteSummaryService` writes drafts, and
what the Bill Creator's `has_testimony` prop says. Sharing one check means
"the system generated positions from this" and "the system will publish
positions from this" can never disagree.

## Why this is not redundant with the per-draft mark

The per-entry evidence-retracted mark (see
[Marking a draft's evidence as retracted](evidence-retraction.md)) is only
ever stamped by one of five writes that each find the evidence was
WITHDRAWN. An operator clearing `supplemental_testimony` out from under
existing drafts is one of them, so the per-entry check usually
answers first, with the more specific `:evidence_retracted`. Three request
paths reach that clear: `PATCH supplemental_testimony`, `generate_summary`,
and `regenerate_summary`.

This bill-level gate owns the two states no mark reaches:

- Drafts that predate the mark entirely — older drafts the mark-retirement
  migration deliberately left unmarked.
- A bill whose testimony went away by some route that wrote no mark at all.

Marks are per-draft; this check is per-bill. Neither subsumes the other. It
runs alongside the per-entry check, not instead of it — a retracted draft on
a bill that has since gained new testimony is still refused by the per-entry
check, which is the correct answer for it.

BLOCK, do not delete: deleting would destroy triage state the operator can
still edit, so refused drafts stay visible and stay editable, just
unapprovable.

## Recovery

Re-pasting cleared testimony is NOT a recovery path, though an older design
claimed it was. Nothing could check that a re-paste matched what was
removed, and on a bill that also carries hearing testimony this gate never
fired on a clear at all — it asks whether testimony is absent, and
`extracted_testimony` kept it present. Regenerate or Reject are the two ways
out, and the Clear button says so before it fires.

## Scope

Because this asks whether testimony is ABSENT, a bill that still CARRIES
supplemental testimony passes — including drafts created before the mark
existed, which the mark-retirement migration deliberately skipped. That's
the right boundary, not an oversight: earlier versions of the positions
prompt were grounded on the supplemental section and told to return `[]`
when it was missing, so drafts sitting on a supplemental-bearing row are
evidenced drafts, and refusing them would assert something false about
them. Two examples are pinned in `approve_org_position_service_spec.rb`,
where re-pasting the testimony turns `:no_testimony` back into `:approved`.
The retirement migration's header quotes the old prompt and the production
counts.

## A missing provisioning row counts as missing testimony

A caller naming a draft index on a bill with no provisioning row is naming a
draft that does not exist, and there is no evidence anywhere to publish
from. Refuse rather than allow.

Like every other guard in this class, this check runs twice: once before
the transaction (reading `@bill.bill_llm_provisioning`) and once again
inside `#delete_approved_draft` against the freshly reloaded row, so another
operator clearing the testimony between the two reads still gets caught. See
[The approval guard chain](org-position-approval-guard-chain.md) for that
pattern in general.

## The Bill Creator warns before it happens

Clear now BLOCKS APPROVAL of every draft position written from this
testimony — warned here, before it happens, rather than at a refused
Approve. The warning only shows when drafts exist, to avoid noise
otherwise.

## Test setup for BillCreatorLlmSummary.test.tsx

Clear asks confirmation first, since it blocks approval on drafts from
removed testimony. A stand-in replaces ConfirmProvider, since this file
already stubs the dialog parts it draws through.
