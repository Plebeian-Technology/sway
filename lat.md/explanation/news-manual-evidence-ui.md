---
lat:
  mode: explanation
---
# Manual summary evidence review controls

The Bill Creator provides news declaration and source-reference controls to verify evidence and ground claims before publication.

## Manual evidence review controls

Manual summary authoring separates statutory bill synthesis from cited news reporting through explicit declarations.

Operators choose between `"none"` and `"cited"` news usage. Declaring no news reporting enforces that the summary prose contains zero external news reporting URLs, while declaring cited reporting validates markdown news links in the summary prose against approved, text-backed articles for the bill without requiring manual claim or excerpt entry in the UI.

### Exclusion of link-only articles

Articles lacking attributable text versions are excluded from synthesis citation eligibility.

While link-only articles remain valid related links elsewhere on public bill pages, synthesis grounding requires underlying text snapshots so cited reporting can be bound to an immutable text version.

## Recoverable draft preservation on validation failure

Rejected manual publications retain summary text as draft revisions. A failed attempt without a captured snapshot does not retain its entered source manifest in that revision.

Rather than discarding typed progress or mutating the public bill summary, failed publication attempts save draft revisions under `publication_role: "draft"`. The rejection path preserves existing public text. [[news-gate#Why manual edits and restorations require evidence validation under lock]] describes how final assessment verdicts are evaluated under lock prior to manual publication.

## Historical legacy restoration

Restoring legacy revisions lacking immutable evidence snapshots creates review drafts rather than replacing live summaries.

[[app/models/bill.rb#Bill#restore_summary_revision!]] retains a legacy restore as a review draft when no declaration is supplied. [[app/serializers/bill_summary_revision_resource.rb#BillSummaryRevisionResource]] emits the snapshot identity (`news_source_snapshot_id` and `has_snapshot`), enabling [[app/frontend/components/admin/creator/llm-summary/BillSummaryRevisionHistory.tsx]] to distinguish snapshot-bearing restorations that publish immediately from snapshotless legacy revisions requiring manual review.

### Editor review and explicit publication

Restoring a legacy revision redirects to the Bill Creator with the draft revision identifier so the editor loads the draft text.

The editor presents an explicit review draft notice and populates its editable draft text while keeping the live public summary untouched. Administrators can declare news usage and save or publish explicitly, or review existing draft revisions directly from revision history without initiating duplicate restoration cycles.
