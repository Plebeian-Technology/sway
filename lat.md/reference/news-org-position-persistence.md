---
lat:
  mode: reference
---

# News organization position persistence

Persistence pipelines filter draft organization positions against source article snapshots before persisting to database columns, guaranteeing zero ungrounded entries and zero unreviewed organization entity creation.

## Position origin and affiliation

Positions are categorized by origin to support affiliation labeling required by SWAY-7prly ("Epic: Make clear that organizations shown on Sway are not affiliated with Sway").

- **Org-posted**: Positions created by members of the organization. Label: "Posted by {Org}".
- **Sway-compiled**: Positions sourced from hearing testimony, news, or admin entry. Label: "Compiled by Sway" and accompanied by an affiliation disclaimer.

## Persistence callers

Four domain execution callers invoke draft position persistence and grounding filters.

| Caller | Source Snapshots | Filter Method | Destination |
| --- | --- | --- | --- |
| [[app/jobs/generate_bill_summary_job.rb#GenerateBillSummaryJob]] | `for_summary` (reporting) and `for_testimony` (commentary) | `NewsOrgPositionGroundingService.filter_draft_positions` | `BillLlmProvisioning#draft_org_positions` |
| [[app/services/summary_batch_item.rb#SummaryBatchItem]] | Captures `for_summary` for reporting and `for_testimony` for commentary | Prompt enclosure formatting | Claude Batch API Item |
| [[app/services/summary_batch_result_persister.rb#SummaryBatchResultPersister]] | `for_summary` and `for_testimony` resolved via run receipts | `NewsOrgPositionGroundingService.filter_draft_positions` | `BillLlmProvisioning#draft_org_positions` |
| [[app/services/paste_summary_service.rb#PasteSummaryService]] | Most recent `for_summary` and `for_testimony` snapshots | `NewsOrgPositionGroundingService.filter_draft_positions` | `BillLlmProvisioning#draft_org_positions` |

## Snapshot resolution matrix

Snapshot resolution maps caller answer types and receipts to the appropriate purpose scope.

| Answer Type | Primary Scope | Secondary Scope |
| --- | --- | --- |
| `SUMMARY` | `for_summary` (`purpose: "summary"`) | None |
| `POSITIONS` | `for_testimony` (`purpose: "testimony"`) | `for_summary` (`purpose: "summary"`) |

## Zero entity creation invariant

Draft position persistence paths strictly update the JSON array on [[app/models/bill_llm_provisioning.rb|BillLlmProvisioning]] and never instantiate or persist public records.

- `Organization` count remains invariant across all summary and positions generation runs.
- `OrganizationBillPosition` count remains invariant until explicit administrator approval.
- User-managed organizations with user memberships are excluded from drafts.

## Approval of news-sourced draft positions

News-sourced draft positions bypass hearing testimony existence checks and require grounded evidence verification alongside user membership safeguards prior to approval.

| Guard | Rule | Failure Outcome |
| --- | --- | --- |
| Testimony Bypass | News-sourced drafts (`bill_news_article_id` present) skip `BillLlmProvisioning#testimony_present?` check. | N/A |
| Grounding Check | Backing news article must remain approved and match `text_version_id` via `NewsOrgPositionGroundingService.entry_still_grounded?`. | `:evidence_retracted` |
| Membership Check | Target organization must have zero `UserOrganizationMembership` rows. | `:organization_has_users` |
| Deduplication | Matching against existing organizations uses normalized exact match followed by Jaro-Winkler distance threshold (0.90). | N/A |
| AI Summary | Sets `ai_summary: nil` on [[app/models/organization_bill_position.rb#OrganizationBillPosition]] since news-sourced positions quote article text verbatim. | N/A |

## Persistence fields

Persistence records the origin of organization positions in [[app/models/organization_bill_position.rb#OrganizationBillPosition]] for public payload serialization.

- `origin`: The provenance of the position ("Org-posted" or "Sway-compiled").
- `origin_url`: The URL to the backing source article or testimony if available.

