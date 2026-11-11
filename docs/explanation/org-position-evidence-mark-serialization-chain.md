---
mode: explanation
summary: "Traces the path the evidence-retracted mark on a draft org position must survive, from BillLlmProvisioning to the client, and what breaks silently if a link drops it."
status: agent-extracted
related: [org-position-approval-guard-chain.md, evidence-retraction.md]
---

<!-- vale Vale.Spelling = NO -->

# The evidence-retracted mark's path to the client

`ApproveOrgPositionService` has two gates: a bill-level testimony check, and
a per-draft mark refusing a draft whose own evidence
(`BillLlmProvisioning.drafts_with_evidence_retracted`, see
[Marking a draft's evidence as retracted](evidence-retraction.md)) has been
withdrawn. The server-side refusal is only half the guarantee — the mark
also has to reach the browser, so the operator sees the warning and the
disabled Approve button before they ever click.

The mark is written into the `draft_org_positions` JSON array, and has to
survive `draft_org_positions_for_client`'s merge, `to_builder`,
`to_sway_json`, and the Inertia `bill` prop, arriving under the exact name
`types.ts` declares. Break any link in that chain and the card's notice
disappears and Approve goes live on a draft whose evidence is proven gone —
with every suite green, because the server-side refusal in
[The approval guard chain](org-position-approval-guard-chain.md) keeps
working and only the warning before the click is lost. A test that hands a
React component a hand-built prop object never exercises this chain; only a
browser spec driving the real page does.
