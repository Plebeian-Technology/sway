---
mode: explanation
summary: "Why rejecting a campaign draft is stored against the bill by content hash, and why a rejected card stays on screen instead of disappearing."
status: agent-extracted
related: ["docs/explanation/campaign-scope-and-identity.md", "docs/explanation/campaign-approval-guard-chain.md"]
---
<!-- vale Vale.Spelling = NO -->

# About rejecting a campaign draft

## The problem: a campaign draft has no row

{#campaign-draft-rejection}
{#stored-decision}

A campaign draft is derived data. The Bill Creator reads it out of the
cleaned-testimony artifact's `groups` array on every request, so it has no
database row and no primary key of its own. Reject was therefore a client-only
`setDismissed(true)`: the operator's decision lived in React state and was gone
on the next page load, and gone again after every re-run of the clean-testimony
stage.

The decision is now stored on `bill_llm_provisionings` in a JSON array column,
`rejected_campaign_draft_hashes`, beside the `draft_org_positions` column that
already solves the same problem for organization drafts.

## Why the key is a content hash

{#identity-is-the-hash}

The stored key is the pair (bill, campaign-draft content hash). The hash is the
draft's own stable id — a SHA-256 digest of the reused text, written by the
grouping stage — so it survives a re-run that reorders unchanged drafts. An
array index does not: a re-run that adds or drops one group renumbers every
draft after it, which would silently move a rejection from one campaign to
another. A database id is not available at all, because there is no row.

The column lives on the provisioning row rather than in the artifact, so a
re-run of the clean-testimony stage rewrites `cleaned_testimony` without
touching the decision.

## Why a rejected card stays visible

{#restore}

A rejected draft renders as a one-line REJECTED record with its own Restore
button rather than vanishing from the list. A decision an operator cannot see
is one they cannot undo, and on a civic transparency platform an operator must
be able to review what was excluded from a bill's record and put it back.

The card reads `rejected` straight off the server prop, so a rejected draft
paints as rejected on first render — there is no client round-trip in which it
briefly appears approvable.

## The activity log

{#activity-log}

Both reject and restore write an `org_position_decision` entry through
`PipelineActivityLogger`, with the draft named by `<bill_id>-campaign-<hash>`,
the same identity shape `ApproveCampaignPositionService` logs. Only a decision
that actually changed the stored list is logged, so a double-click does not
produce two entries.
