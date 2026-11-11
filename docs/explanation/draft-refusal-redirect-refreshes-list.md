---
mode: explanation
summary: "Explains why the Bill Creator's draft-decision refusals redirect to the Summary tab instead of asking for a manual reload, and what the regression suite measures."
status: agent-extracted
related: [docs/explanation/summary-run-release-message-history.md]
---

<!-- vale Vale.Spelling = NO -->

# Draft-decision refusals refresh the list on their own

Two refusals on the Bill Creator's Summary tab used to end with "reload and
try again." No surface in this project may require a manual refresh, and
these two never needed to ask for one in the first place: both refuse by
redirecting to `summary_bill_creator_path`, and that `GET` renders the Bill
Creator again with the current draft list. The operator is looking at the
fresh list by the time the refusal's toast reaches them.

`DraftOrgPositionRefusals::LIST_CHANGED` states that claim in prose;
`spec/requests/draft_list_refusal_refreshes_the_list_spec.rb` measures it.
The examples follow the redirect and read the draft list out of the Inertia
props that come back, so a change that broke the refresh — answering 422
instead of redirecting, redirecting somewhere that does not carry the bill,
or dropping `draft_org_positions` from the props — fails there rather than
shipping a message that quietly became a lie.
