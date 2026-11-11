---
mode: reference
summary: "Catalogs the Symbol outcomes ApproveOrgPositionService#call can return and what each one means."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# ApproveOrgPositionService outcomes

`ApproveOrgPositionService#call` returns one Symbol. The controller
(`BillsController#approve_org_position`) maps it to a redirect: an error
message on a failure outcome, a flash notice on `:approved`.

| Outcome | Meaning |
|---|---|
| `:org_name_required` | `org_name` was blank after stripping whitespace. |
| `:summary_required` | `summary` was blank after stripping whitespace. |
| `:invalid_stance` | `support` did not normalize to a known stance. |
| `:identity_required` | The caller sent an `:index` but named no draft (no `draft_org_name` or `draft_token`). |
| `:draft_index_required` | The caller named a draft but sent no `:index` saying where it sits. |
| `:draft_index_mismatch` | `:index` does not point at the draft the caller named. |
| `:evidence_retracted` | The named draft's testimony evidence was withdrawn. |
| `:no_testimony` | The bill has no testimony left at all. |
| `:run_in_flight` | A summary run is queued or already running on this bill. |
| `:approved` | The organization and position were upserted, the draft was removed, and the decision was logged. |

See [Draft identity and the approval exemption](../explanation/org-position-draft-identity-exemption.md)
for `:identity_required` and `:draft_index_required`, and
[The approval guard chain](../explanation/org-position-approval-guard-chain.md)
for `:draft_index_mismatch`, `:evidence_retracted`, `:no_testimony`, and
`:run_in_flight`.
