---
lat:
  mode: reference
---

# ApproveCampaignPositionService outcomes

`ApproveCampaignPositionService#call` returns one Symbol.

- The controller (`CampaignsController#create`) maps it to a redirect: an error message on a failure outcome, a flash notice on `:approved`. The guards run in the order below; the first one that trips is the outcome, and nothing is written.

| Outcome | Meaning |
|---|---|
| `:summary_required` | `summary` was blank after stripping whitespace. |
| `:invalid_stance` | `support` did not normalize to a known stance. |
| `:identity_required` | The caller sent no `content_hash` naming a draft. |
| `:draft_not_found` | No draft in the bill's current artifact carries the `content_hash` the caller named. |
| `:run_in_flight` | A clean-testimony run is queued or already running on this bill. |
| `:no_testimony` | The bill has no testimony left at all. |
| `:coverage_not_acknowledged` | Testimony was left out and no acknowledgement matches the current numbers. |
| `:approved` | The campaign was written and the decision was logged. |
| `:approved_replacing_draft` | The same, and this name already carried a decision approved from a *different* draft, which this one replaced. |

- Two of these are successes. `:approved_replacing_draft` is not a refusal and nothing is rolled back — it is the same write, reported differently because the operator is overwriting a decision they may not remember making. See [[docs/explanation/campaign-scope-and-identity.md|About campaign scope and identity]] for why the write is allowed to stand rather than being refused.

- `content_hash` is the only identity this service accepts. It once required a `:index` as well, which is why an `:draft_index_required` and a `:draft_index_mismatch` outcome appear in older notes; both are gone. See [[docs/explanation/campaign-approval-guard-chain.md|The campaign approval guard chain]] for what each remaining guard is protecting.

- The organization-side catalog is [[docs/reference/approve-org-position-outcomes.md|ApproveOrgPositionService outcomes]].
