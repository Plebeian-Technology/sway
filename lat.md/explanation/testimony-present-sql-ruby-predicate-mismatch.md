---
lat:
  mode: explanation
---

# The SQL predicate must match testimony_present? exactly (D-IN-03)

`db/data/20260726000002_retire_untestified_draft_org_positions` marks a draft's evidence as retracted when a row holds draft org positions while both testimony columns are empty.

The migration's header quotes `BillLlmProvisioning#testimony_present?`, which is a `.present?` check.

An earlier version of the migration's SQL asked a different question — `IN (NULL, '')` — so a row whose only testimony was whitespace answered "no testimony" everywhere else in the system (the check before positions are generated, the Bill Creator's `has_testimony`, `ApproveOrgPositionService`'s bill-level check) and "has testimony" in this migration's SQL, and kept its drafts approvable.

No such rows exist in real data, so this has never bitten anyone. It is pinned anyway: a check that disagrees with the one it claims to use is a recurring class of defect in this area of the codebase, and whitespace is exactly what pasting an empty text box leaves behind.

## Not the same as the supplemental_testimony widening

This whitespace fix is not the widening that production data ruled out and that must stay ruled out: a row carrying real supplemental testimony still keeps its drafts.

Whitespace is not testimony by the system's own definition (`.present?` is false on whitespace-only strings), but real pasted text is.
